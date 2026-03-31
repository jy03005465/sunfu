"""
智能文本切分模块

支持多种切分策略：
- 按段落切分
- 按句子切分
- 按固定长度切分（带重叠）
- Markdown 感知切分（尊重标题、代码块等结构）
- 自动选择最优切分策略
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto


class SplitStrategy(Enum):
    AUTO = auto()
    PARAGRAPH = auto()
    SENTENCE = auto()
    FIXED_SIZE = auto()
    MARKDOWN = auto()


@dataclass
class TextChunk:
    text: str
    chunk_index: int
    total_chunks: int
    start_pos: int
    end_pos: int
    metadata: dict = field(default_factory=dict)

    @property
    def char_count(self) -> int:
        return len(self.text)


def _detect_strategy(text: str) -> SplitStrategy:
    """根据文本内容自动选择最合适的切分策略"""
    md_pattern_count = len(re.findall(r'^#{1,6}\s', text, re.MULTILINE))
    if md_pattern_count >= 2:
        return SplitStrategy.MARKDOWN

    paragraphs = re.split(r'\n\s*\n', text.strip())
    avg_para_len = sum(len(p) for p in paragraphs) / max(len(paragraphs), 1)
    if len(paragraphs) >= 3 and 50 < avg_para_len < 2000:
        return SplitStrategy.PARAGRAPH

    return SplitStrategy.FIXED_SIZE


def _split_by_paragraph(text: str, max_chunk_size: int = 500, min_chunk_size: int = 50) -> list[str]:
    """按段落切分，过短的段落会合并到相邻块"""
    paragraphs = re.split(r'\n\s*\n', text.strip())
    paragraphs = [p.strip() for p in paragraphs if p.strip()]

    chunks: list[str] = []
    current = ""

    for para in paragraphs:
        candidate = f"{current}\n\n{para}".strip() if current else para
        if len(candidate) > max_chunk_size and current:
            chunks.append(current)
            current = para
        else:
            current = candidate

    if current and len(current) >= min_chunk_size:
        chunks.append(current)
    elif current and chunks:
        chunks[-1] = f"{chunks[-1]}\n\n{current}"
    elif current:
        chunks.append(current)

    return chunks


_SENTENCE_RE = re.compile(
    r'(?<=[。！？.!?])\s*'
    r'|(?<=\n)\s*'
)


def _split_by_sentence(text: str, max_chunk_size: int = 500, min_chunk_size: int = 50) -> list[str]:
    """按句子切分，保证语义完整性"""
    sentences = _SENTENCE_RE.split(text.strip())
    sentences = [s.strip() for s in sentences if s.strip()]

    chunks: list[str] = []
    current = ""

    for sent in sentences:
        candidate = f"{current} {sent}".strip() if current else sent
        if len(candidate) > max_chunk_size and current:
            chunks.append(current)
            current = sent
        else:
            current = candidate

    if current and len(current) >= min_chunk_size:
        chunks.append(current)
    elif current and chunks:
        chunks[-1] = f"{chunks[-1]} {current}"
    elif current:
        chunks.append(current)

    return chunks


def _split_fixed_size(text: str, chunk_size: int = 500, overlap: int = 50) -> list[str]:
    """按固定字符数切分，带重叠区域保证上下文连续"""
    text = text.strip()
    if not text:
        return []
    if len(text) <= chunk_size:
        return [text]

    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunk = text[start:end]

        if end < len(text):
            for sep in ['\n', '。', '！', '？', '.', '!', '?', '，', ',', ' ']:
                last_sep = chunk.rfind(sep)
                if last_sep > chunk_size * 0.3:
                    end = start + last_sep + 1
                    chunk = text[start:end]
                    break

        chunks.append(chunk.strip())
        start = max(start + 1, end - overlap)

    return [c for c in chunks if c]


_MD_HEADING_RE = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)


def _split_markdown(text: str, max_chunk_size: int = 800) -> list[str]:
    """Markdown 感知切分，按标题层级拆分并保留层级路径"""
    sections: list[tuple[str, str]] = []
    lines = text.split('\n')

    current_heading = ""
    current_content: list[str] = []

    for line in lines:
        heading_match = _MD_HEADING_RE.match(line)
        if heading_match:
            if current_content:
                content_text = '\n'.join(current_content).strip()
                if content_text:
                    sections.append((current_heading, content_text))
            current_heading = line
            current_content = []
        else:
            current_content.append(line)

    if current_content:
        content_text = '\n'.join(current_content).strip()
        if content_text:
            sections.append((current_heading, content_text))

    chunks: list[str] = []
    for heading, content in sections:
        full = f"{heading}\n{content}".strip() if heading else content
        if len(full) <= max_chunk_size:
            chunks.append(full)
        else:
            sub_chunks = _split_fixed_size(full, chunk_size=max_chunk_size, overlap=50)
            chunks.extend(sub_chunks)

    return [c for c in chunks if c.strip()]


def split_text(
    text: str,
    strategy: SplitStrategy = SplitStrategy.AUTO,
    chunk_size: int = 500,
    overlap: int = 50,
    min_chunk_size: int = 50,
    metadata: dict | None = None,
) -> list[TextChunk]:
    """
    智能切分文本，返回 TextChunk 列表。

    参数:
        text: 待切分的原始文本
        strategy: 切分策略 (AUTO 时自动检测)
        chunk_size: 每个块的目标字符数
        overlap: 固定长度切分时的重叠字符数
        min_chunk_size: 最小块字符数，低于此值会合并
        metadata: 附加到每个 chunk 的额外元数据
    """
    if not text or not text.strip():
        return []

    if strategy == SplitStrategy.AUTO:
        strategy = _detect_strategy(text)

    if strategy == SplitStrategy.PARAGRAPH:
        raw_chunks = _split_by_paragraph(text, max_chunk_size=chunk_size, min_chunk_size=min_chunk_size)
    elif strategy == SplitStrategy.SENTENCE:
        raw_chunks = _split_by_sentence(text, max_chunk_size=chunk_size, min_chunk_size=min_chunk_size)
    elif strategy == SplitStrategy.MARKDOWN:
        raw_chunks = _split_markdown(text, max_chunk_size=chunk_size)
    else:
        raw_chunks = _split_fixed_size(text, chunk_size=chunk_size, overlap=overlap)

    total = len(raw_chunks)
    base_meta = metadata or {}
    chunks: list[TextChunk] = []
    pos = 0

    for i, raw in enumerate(raw_chunks):
        start = text.find(raw[:40], pos)
        if start == -1:
            start = pos
        end = start + len(raw)

        chunks.append(TextChunk(
            text=raw,
            chunk_index=i,
            total_chunks=total,
            start_pos=start,
            end_pos=end,
            metadata={**base_meta},
        ))
        pos = start + 1

    return chunks
