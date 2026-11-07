# Wiki Index (`wiki/_index.md`)

B-Tree Root Router for the Repo Nexus Karpathy LLM Wiki. Query shards in `_index/` or relationships via `_graph/`.

## 1. Repo Nexus (Root Repository)

| Shard Index File | Key Range (`LC_ALL=C`) | Entries | Scope |
| :--- | :--- | :--- | :--- |
| [`_index/repo-nexus.md`](_index/repo-nexus.md) | *(empty)* | 0 | Nexus workspace sources & architecture |

## 2. Member Repositories

| Member Repo Shard | Repository Scope | Key Range (`LC_ALL=C`) | Entries |
| :--- | :--- | :--- | :--- |

## 3. Property Graph Store (`_graph/`)

- **Nodes Indexed:** 0 (`_graph/nodes.tsv`)
- **Directed Edges:** 0 (`_graph/edges_out.tsv` & `_graph/edges_in.tsv`)
