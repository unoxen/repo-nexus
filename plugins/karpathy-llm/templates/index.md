# Wiki Index (B-Tree Root Router)

Compact root routing table for the Karpathy LLM Wiki. Do not list individual pages here; follow the matching B-Tree shard in `_index/` or query the sorted TSV graph in `_graph/`.

## 1. B-Tree Domain Shards (`_index/`)

| Shard File | Key Range (`LC_ALL=C`) | Entries | Domain Scope |
| :--- | :--- | :--- | :--- |
| [`_index/concepts.md`](_index/concepts.md) | *(empty)* | 0 | Core domain concepts, patterns, and design protocols |
| [`_index/entities.md`](_index/entities.md) | *(empty)* | 0 | Concrete modules, services, CLI binaries, and components |
| [`_index/overview.md`](_index/overview.md) | *(empty)* | 0 | High-level workspace architecture and system summaries |
| [`_index/sources.md`](_index/sources.md) | *(empty)* | 0 | Ingested raw source document summaries and provenance |

## 2. Sorted TSV Property Graph (`_graph/`)

- **Total Indexed Nodes:** 0 (`_graph/nodes.tsv`)
- **Total Directed Edges:** 0 (`_graph/edges_out.tsv` & `_graph/edges_in.tsv`)
- **Fast Prefix Search:** `rnex plugin karpathy-llm search <prefix>`
- **Subgraph Traversal:** `rnex plugin karpathy-llm graph <node_id> --depth 1`
- **Recent Audit History:** `tail -n 20 _log.md`
