"""
Qdrant 知识库连接客户端
服务器地址: http://101.132.184.213:6333
"""

from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct


QDRANT_HOST = "101.132.184.213"
QDRANT_PORT = 6333
QDRANT_URL = f"http://{QDRANT_HOST}:{QDRANT_PORT}"


def get_client() -> QdrantClient:
    """获取 Qdrant 客户端实例"""
    return QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)


def list_collections(client: QdrantClient) -> list:
    """列出所有集合"""
    return client.get_collections().collections


def get_collection_info(client: QdrantClient, collection_name: str):
    """获取指定集合的详细信息"""
    return client.get_collection(collection_name)


def search_vectors(
    client: QdrantClient,
    collection_name: str,
    query_vector: list[float],
    limit: int = 5,
):
    """在指定集合中搜索最相似的向量"""
    return client.query_points(
        collection_name=collection_name,
        query=query_vector,
        limit=limit,
    )


def scroll_points(
    client: QdrantClient,
    collection_name: str,
    limit: int = 10,
    offset=None,
):
    """分页浏览集合中的数据点"""
    return client.scroll(
        collection_name=collection_name,
        limit=limit,
        offset=offset,
        with_payload=True,
        with_vectors=False,
    )


if __name__ == "__main__":
    client = get_client()

    print("=" * 50)
    print("Qdrant 知识库连接测试")
    print("=" * 50)

    collections = list_collections(client)
    print(f"\n已连接到: {QDRANT_URL}")
    print(f"集合数量: {len(collections)}")

    for col in collections:
        info = get_collection_info(client, col.name)
        print(f"\n--- 集合: {col.name} ---")
        print(f"  数据点数量: {info.points_count}")
        print(f"  向量维度:   {info.config.params.vectors.size}")
        print(f"  距离度量:   {info.config.params.vectors.distance}")
        print(f"  状态:       {info.status}")

        points, next_offset = scroll_points(client, col.name, limit=3)
        if points:
            print(f"  前 {len(points)} 条数据预览:")
            for p in points:
                payload_preview = str(p.payload)[:100] if p.payload else "(无载荷)"
                print(f"    ID={p.id}: {payload_preview}")

    print("\n" + "=" * 50)
    print("连接测试完成!")
    print("=" * 50)
