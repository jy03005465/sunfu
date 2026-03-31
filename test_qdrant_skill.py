"""
Qdrant 知识库 Skill 功能测试

测试三大核心功能:
  1. 读取库
  2. 读取库中的知识
  3. 智能切分并存储知识
"""

from qdrant_skill import QdrantKnowledgeSkill
from text_splitter import SplitStrategy, split_text

TEST_COLLECTION = "_skill_test_tmp"

SAMPLE_TEXT = """# 智能印染系统概述

智能印染系统是纺织行业数字化转型的重要组成部分，通过物联网传感器、AI 算法和大数据分析，实现染色过程的精准控制。

## 核心功能

### 1. 智能配色
利用光谱分析和深度学习模型，自动匹配最优染料配方。系统内置超过十万种颜色样本数据库，可在 30 秒内完成配色方案生成。

### 2. 工艺优化
基于历史染色数据和实时传感器反馈，动态调整温度、时间、浴比等参数，确保每批次染色质量稳定一致。

### 3. 质量监控
全流程颜色 QC 跟踪体系，从标准样到实验室打色、复版、头缸、批次，实时采集各环节数据，异常数据自动标记并预警。

## 技术架构

系统采用边缘计算 + 云端协同架构。边缘端部署轻量化 AI 推理模型，实现毫秒级响应；云端负责模型训练、数据分析和远程管理。

通信层采用 MQTT + OPC UA 双协议，兼容主流 PLC 和 DCS 系统，实现设备无缝接入。
"""


def separator(title: str):
    print(f"\n{'=' * 60}")
    print(f"  {title}")
    print(f"{'=' * 60}")


def test_text_splitter():
    """测试智能文本切分"""
    separator("测试: 智能文本切分")

    for strategy in [SplitStrategy.AUTO, SplitStrategy.PARAGRAPH, SplitStrategy.MARKDOWN, SplitStrategy.FIXED_SIZE]:
        chunks = split_text(SAMPLE_TEXT, strategy=strategy, chunk_size=300)
        print(f"\n策略 [{strategy.name}] → {len(chunks)} 个块:")
        for c in chunks:
            print(f"  块{c.chunk_index}: {c.char_count}字 | pos=[{c.start_pos}:{c.end_pos}] | {c.text[:50]}…")

    print("\n✓ 文本切分测试通过")


def test_list_collections(skill: QdrantKnowledgeSkill):
    """测试功能1: 读取库"""
    separator("功能1: 读取库")

    collections = skill.list_collections()
    print(f"共 {len(collections)} 个集合:\n")
    for col in collections:
        print(f"  {col}")

    detail = skill.get_collection_detail(collections[0].name)
    print(f"\n集合 [{collections[0].name}] 详情:")
    for k, v in detail.items():
        print(f"  {k}: {v}")

    print("\n✓ 读取库测试通过")


def test_read_knowledge(skill: QdrantKnowledgeSkill):
    """测试功能2: 读取库中的知识"""
    separator("功能2: 读取库中的知识")

    col_name = skill.list_collections()[0].name
    total = skill.count_knowledge(col_name)
    print(f"[{col_name}] 共 {total} 条知识\n")

    print("--- 分页浏览 (前5条) ---")
    items, next_offset = skill.browse_knowledge(col_name, limit=5)
    for item in items:
        print(f"  {item}")
    print(f"  下一页偏移: {next_offset}")

    if items:
        print(f"\n--- 按ID获取: {items[0].id} ---")
        single = skill.get_knowledge_by_id(col_name, items[0].id)
        if single:
            print(f"  来源: {single.source}")
            print(f"  元数据: {list(single.metadata.keys())}")
            print(f"  正文: {single.text[:200]}…")

    print("\n✓ 读取知识测试通过")


def test_store_knowledge(skill: QdrantKnowledgeSkill):
    """测试功能3: 智能切分并存储知识"""
    separator("功能3: 智能切分并存储知识")

    if skill.collection_exists(TEST_COLLECTION):
        skill.delete_collection(TEST_COLLECTION)
        print(f"已清理旧测试集合 [{TEST_COLLECTION}]")

    result = skill.store_knowledge(
        collection_name=TEST_COLLECTION,
        text=SAMPLE_TEXT,
        source="test_document.md",
        author="测试脚本",
        category="测试",
        chunk_size=300,
    )

    print(f"\n存储结果: {result}")
    print(f"  集合: {result.collection_name}")
    print(f"  切分块数: {result.total_chunks}")
    print(f"  切分策略: {result.strategy_used}")
    print(f"  文本指纹: {result.source_fingerprint}")
    print(f"  存储ID列表: {result.stored_ids[:3]}…")

    print(f"\n--- 回读验证 ---")
    stored_items = skill.get_all_knowledge(TEST_COLLECTION)
    print(f"  回读到 {len(stored_items)} 条知识")
    for item in stored_items[:3]:
        print(f"  [{item.id}] chunk={item.metadata.get('chunk_index', '?')} | {item.text[:60]}…")

    print(f"\n--- 按来源过滤 ---")
    filtered = skill.filter_knowledge_by_source(TEST_COLLECTION, "test_document.md")
    print(f"  来源='test_document.md' → {len(filtered)} 条")

    skill.delete_collection(TEST_COLLECTION)
    print(f"\n已清理测试集合 [{TEST_COLLECTION}]")

    print("\n✓ 智能切分并存储测试通过")


if __name__ == "__main__":
    print("Qdrant 知识库 Skill 功能测试")
    print("服务器: http://101.132.184.213:6333\n")

    skill = QdrantKnowledgeSkill()

    test_text_splitter()
    test_list_collections(skill)
    test_read_knowledge(skill)
    test_store_knowledge(skill)

    separator("全部测试通过 ✓")
