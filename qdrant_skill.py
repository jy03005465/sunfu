"""
Qdrant 知识库 Skill

三大核心能力:
  1. 读取库 —— 列出/查看集合信息
  2. 读取库中的知识 —— 分页浏览、按 ID 获取、全文检索
  3. 智能切分并存储知识 —— 自动切分文本，生成向量并入库
"""

from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    FieldCondition,
    Filter,
    MatchValue,
    PointStruct,
    VectorParams,
)

from text_splitter import SplitStrategy, TextChunk, split_text


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
QDRANT_HOST = "101.132.184.213"
QDRANT_PORT = 6333
DEFAULT_VECTOR_SIZE = 1024
DEFAULT_DISTANCE = Distance.COSINE


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------
@dataclass
class CollectionSummary:
    name: str
    points_count: int
    vector_size: int
    distance: str
    status: str

    def __str__(self) -> str:
        return (
            f"[{self.name}] {self.points_count} 条知识 | "
            f"维度={self.vector_size} | 距离={self.distance} | 状态={self.status}"
        )


@dataclass
class KnowledgeItem:
    id: str
    text: str
    source: str = ""
    metadata: dict = field(default_factory=dict)

    def __str__(self) -> str:
        preview = self.text[:120].replace("\n", " ")
        return f"[{self.id}] {preview}..."


@dataclass
class StoreResult:
    collection_name: str
    total_chunks: int
    stored_ids: list[str]
    strategy_used: str
    source_fingerprint: str

    def __str__(self) -> str:
        return (
            f"已存储 {self.total_chunks} 个知识块到 [{self.collection_name}] | "
            f"策略={self.strategy_used} | 指纹={self.source_fingerprint[:12]}…"
        )


# ---------------------------------------------------------------------------
# 核心 Skill 类
# ---------------------------------------------------------------------------
class QdrantKnowledgeSkill:
    """Qdrant 知识库技能: 读库 / 读知识 / 切分存储"""

    def __init__(
        self,
        host: str = QDRANT_HOST,
        port: int = QDRANT_PORT,
        embedding_fn=None,
        default_vector_size: int = DEFAULT_VECTOR_SIZE,
    ):
        """
        参数:
            host / port: Qdrant 服务地址
            embedding_fn: 可选的嵌入函数 (text -> list[float])。
                          未提供时使用内置的简单哈希向量（仅供测试，不具备语义能力）。
            default_vector_size: 创建新集合时的默认向量维度
        """
        self.client = QdrantClient(host=host, port=port)
        self._embedding_fn = embedding_fn
        self._vector_size = default_vector_size

    # ====================================================================
    # 功能 1: 读取库
    # ====================================================================

    def list_collections(self) -> list[CollectionSummary]:
        """列出 Qdrant 中所有集合及其基本信息"""
        raw = self.client.get_collections().collections
        results: list[CollectionSummary] = []
        for col in raw:
            info = self.client.get_collection(col.name)
            vec_cfg = info.config.params.vectors
            if isinstance(vec_cfg, dict):
                first_key = next(iter(vec_cfg))
                size = vec_cfg[first_key].size
                dist = vec_cfg[first_key].distance.value
            else:
                size = vec_cfg.size
                dist = vec_cfg.distance.value
            results.append(CollectionSummary(
                name=col.name,
                points_count=info.points_count or 0,
                vector_size=size,
                distance=dist,
                status=str(info.status),
            ))
        return results

    def get_collection_detail(self, collection_name: str) -> dict[str, Any]:
        """获取指定集合的详细配置和统计信息"""
        info = self.client.get_collection(collection_name)
        vec_cfg = info.config.params.vectors
        if isinstance(vec_cfg, dict):
            first_key = next(iter(vec_cfg))
            vec_info = {"size": vec_cfg[first_key].size, "distance": vec_cfg[first_key].distance.value}
        else:
            vec_info = {"size": vec_cfg.size, "distance": vec_cfg.distance.value}

        return {
            "name": collection_name,
            "status": str(info.status),
            "points_count": info.points_count,
            "indexed_vectors_count": info.indexed_vectors_count,
            "segments_count": info.segments_count,
            "vector": vec_info,
            "optimizer_status": str(info.optimizer_status),
        }

    def collection_exists(self, collection_name: str) -> bool:
        """检查集合是否存在"""
        return self.client.collection_exists(collection_name)

    def create_collection(
        self,
        collection_name: str,
        vector_size: int | None = None,
        distance: Distance = DEFAULT_DISTANCE,
        on_disk_payload: bool = True,
    ) -> bool:
        """创建新集合（如已存在则跳过）"""
        if self.collection_exists(collection_name):
            return False
        size = vector_size or self._vector_size
        self.client.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(size=size, distance=distance),
            on_disk_payload=on_disk_payload,
        )
        return True

    def delete_collection(self, collection_name: str) -> bool:
        """删除指定集合"""
        if not self.collection_exists(collection_name):
            return False
        self.client.delete_collection(collection_name)
        return True

    # ====================================================================
    # 功能 2: 读取库中的知识
    # ====================================================================

    def browse_knowledge(
        self,
        collection_name: str,
        limit: int = 10,
        offset=None,
    ) -> tuple[list[KnowledgeItem], Any]:
        """分页浏览集合中的知识条目，返回 (items, next_offset)"""
        points, next_offset = self.client.scroll(
            collection_name=collection_name,
            limit=limit,
            offset=offset,
            with_payload=True,
            with_vectors=False,
        )
        items = [self._point_to_item(p) for p in points]
        return items, next_offset

    def get_all_knowledge(self, collection_name: str, batch_size: int = 100) -> list[KnowledgeItem]:
        """获取集合中的全部知识条目"""
        all_items: list[KnowledgeItem] = []
        offset = None
        while True:
            items, offset = self.browse_knowledge(collection_name, limit=batch_size, offset=offset)
            all_items.extend(items)
            if offset is None:
                break
        return all_items

    def get_knowledge_by_id(self, collection_name: str, point_id: str) -> KnowledgeItem | None:
        """按 ID 获取单条知识"""
        points = self.client.retrieve(
            collection_name=collection_name,
            ids=[point_id],
            with_payload=True,
            with_vectors=False,
        )
        if not points:
            return None
        return self._point_to_item(points[0])

    def search_knowledge(
        self,
        collection_name: str,
        query_text: str,
        limit: int = 5,
    ) -> list[tuple[KnowledgeItem, float]]:
        """通过文本语义搜索知识（需要 embedding_fn）"""
        vector = self._embed(query_text)
        results = self.client.query_points(
            collection_name=collection_name,
            query=vector,
            limit=limit,
            with_payload=True,
        )
        items_with_score: list[tuple[KnowledgeItem, float]] = []
        for sp in results.points:
            item = self._point_to_item(sp)
            items_with_score.append((item, sp.score))
        return items_with_score

    def filter_knowledge_by_source(
        self,
        collection_name: str,
        source: str,
        limit: int = 100,
    ) -> list[KnowledgeItem]:
        """按来源过滤知识条目"""
        for field_name in ("source", "source_file"):
            try:
                points, _ = self.client.scroll(
                    collection_name=collection_name,
                    scroll_filter=Filter(must=[
                        FieldCondition(key=field_name, match=MatchValue(value=source))
                    ]),
                    limit=limit,
                    with_payload=True,
                    with_vectors=False,
                )
                if points:
                    return [self._point_to_item(p) for p in points]
            except Exception:
                continue
        return []

    def count_knowledge(self, collection_name: str) -> int:
        """返回集合中知识条目总数"""
        info = self.client.get_collection(collection_name)
        return info.points_count or 0

    # ====================================================================
    # 功能 3: 智能切分并存储知识
    # ====================================================================

    def store_knowledge(
        self,
        collection_name: str,
        text: str,
        source: str = "",
        author: str = "",
        category: str = "",
        strategy: SplitStrategy = SplitStrategy.AUTO,
        chunk_size: int = 500,
        overlap: int = 50,
        extra_metadata: dict | None = None,
    ) -> StoreResult:
        """
        智能切分文本并存储到 Qdrant 集合中。

        流程:
          1. 计算文本指纹（去重用）
          2. 按策略智能切分文本
          3. 为每个 chunk 生成向量
          4. 写入 Qdrant

        参数:
            collection_name: 目标集合名称（不存在则自动创建）
            text: 待存储的完整文本
            source: 来源标识（文件名、URL 等）
            author: 作者
            category: 分类标签
            strategy: 切分策略
            chunk_size: 每块目标字符数
            overlap: 固定切分重叠字符数
            extra_metadata: 附加元数据
        """
        self.create_collection(collection_name)

        fingerprint = hashlib.md5(text.encode("utf-8")).hexdigest()

        meta = {
            "source_file": source,
            "author": author,
            "category": category,
        }
        if extra_metadata:
            meta.update(extra_metadata)

        chunks = split_text(
            text=text,
            strategy=strategy,
            chunk_size=chunk_size,
            overlap=overlap,
            metadata=meta,
        )

        if not chunks:
            return StoreResult(
                collection_name=collection_name,
                total_chunks=0,
                stored_ids=[],
                strategy_used=strategy.name,
                source_fingerprint=fingerprint,
            )

        points: list[PointStruct] = []
        stored_ids: list[str] = []
        now_str = datetime.now(timezone.utc).isoformat()

        for chunk in chunks:
            vector = self._embed(chunk.text)
            point_id = str(uuid.uuid4())
            stored_ids.append(point_id)

            payload = {
                "text_segment": chunk.text,
                "chunk_index": chunk.chunk_index,
                "total_chunks": chunk.total_chunks,
                "start_pos": chunk.start_pos,
                "end_pos": chunk.end_pos,
                "source_file": source,
                "author": author,
                "category": category,
                "source_fingerprint": fingerprint,
                "stored_at": now_str,
            }
            if extra_metadata:
                payload.update(extra_metadata)

            points.append(PointStruct(
                id=point_id,
                vector=vector,
                payload=payload,
            ))

        batch_size = 64
        for i in range(0, len(points), batch_size):
            self.client.upsert(
                collection_name=collection_name,
                points=points[i : i + batch_size],
            )

        strategy_name = strategy.name
        if strategy == SplitStrategy.AUTO:
            from text_splitter import _detect_strategy
            strategy_name = f"AUTO→{_detect_strategy(text).name}"

        return StoreResult(
            collection_name=collection_name,
            total_chunks=len(chunks),
            stored_ids=stored_ids,
            strategy_used=strategy_name,
            source_fingerprint=fingerprint,
        )

    def store_knowledge_from_file(
        self,
        collection_name: str,
        file_path: str,
        encoding: str = "utf-8",
        author: str = "",
        category: str = "",
        strategy: SplitStrategy = SplitStrategy.AUTO,
        chunk_size: int = 500,
        overlap: int = 50,
        extra_metadata: dict | None = None,
    ) -> StoreResult:
        """读取本地文件内容并智能切分存储"""
        import os
        with open(file_path, "r", encoding=encoding) as f:
            text = f.read()
        source = os.path.basename(file_path)
        return self.store_knowledge(
            collection_name=collection_name,
            text=text,
            source=source,
            author=author,
            category=category,
            strategy=strategy,
            chunk_size=chunk_size,
            overlap=overlap,
            extra_metadata=extra_metadata,
        )

    # ====================================================================
    # 内部工具
    # ====================================================================

    def _embed(self, text: str) -> list[float]:
        """文本 → 向量。优先使用外部 embedding_fn，否则使用哈希模拟向量。"""
        if self._embedding_fn is not None:
            return self._embedding_fn(text)
        return self._hash_embed(text, self._vector_size)

    @staticmethod
    def _hash_embed(text: str, dim: int) -> list[float]:
        """
        基于 SHA-256 的确定性伪向量生成（仅供测试/演示）。
        不具备语义能力，生产环境请替换为真实 embedding 模型。
        """
        h = hashlib.sha256(text.encode("utf-8")).digest()
        import struct
        vec: list[float] = []
        seed = int.from_bytes(h[:8], "little")
        a, c, m = 1664525, 1013904223, 2**32
        for _ in range(dim):
            seed = (a * seed + c) % m
            vec.append((seed / m) * 2 - 1)
        norm = max(sum(v * v for v in vec) ** 0.5, 1e-10)
        return [v / norm for v in vec]

    @staticmethod
    def _point_to_item(point) -> KnowledgeItem:
        """将 Qdrant Point 转换为 KnowledgeItem"""
        payload = point.payload or {}
        text = payload.get("text_segment") or payload.get("text") or ""
        source = payload.get("source_file") or payload.get("source") or ""
        meta = {k: v for k, v in payload.items() if k not in ("text_segment", "text", "source_file", "source")}
        return KnowledgeItem(
            id=str(point.id),
            text=text,
            source=source,
            metadata=meta,
        )
