## 🏗️ Architecture Diagram
```
                    ┌───────────────┐
                    │    Users      │
                    └───────┬───────┘
                            │
                    ┌───────▼────────┐
                    │ K8s Service    │
                    └───────┬────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
        ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
        │ App Pod 1 │ │ App Pod 2 │ │ App Pod 3 │
        └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
              │             │             │
              └─────────────┼─────────────┘
                            │
                  ┌─────────▼─────────┐
                  │ SymmetricDS Pods  │
                  └─────────┬─────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                                       │
 ┌──────▼────────┐                    ┌─────────▼──────┐
 │ postgres-0    │                    │ postgres-1     │
 │ (Primary)     │ ⇄ Replication ⇄   │ (Replica)      │
 └───────────────┘                    └───────────────┘

```



# 📘 SymmetricDS + PostgreSQL Bidirectional Sync Setup (Full Documentation)

---

# 🧭 Overview

This setup creates a **2-database architecture** with:

* **Server DB (Primary)** → `serverdb`
* **Client DB (Secondary)** → `clientdb`
* **SymmetricDS** for real-time + bidirectional sync
* **pgAdmin** for UI management

---

# 🏗️ Architecture

```
ServerDB (Primary)  ⇄  SymmetricDS  ⇄  ClientDB (Secondary)
        ↑                                      ↑
     Writes                              Reads / Writes
```

---

# ⚙️ Step 1: Start Services

```bash
docker-compose up -d
```

---

# 🌐 Step 2: Access pgAdmin

Open browser:

```
http://localhost:5050
```

### Login Credentials:

* Email: `admin@admin.com`
* Password: `admin`

---

# 🖥️ Step 3: Add Databases in pgAdmin

## ➤ ServerDB

* Name: `ServerDB`
* Host: `db_server`
* Port: `5432`
* User: `postgres`
* Password: `postgres`

## ➤ ClientDB

* Name: `ClientDB`
* Host: `db_client`
* Port: `5432`
* User: `postgres`
* Password: `postgres`

---

# 🔌 Step 4: Start Core Services

```bash
docker compose up -d symmetricds_server db_server
```

Enable client registration:

```bash
docker exec -it symmetricds_server bin/symadmin --engine server open-registration client 001
```

Start client:

```bash
docker compose up -d symmetricds_client db_client
```

---

# 🧠 Step 5: Configure Sync (Server Side)

Connect to server DB:

```bash
docker exec -it db_server psql -U postgres -d serverdb
```

## ➤ Create Router (Server → Client)

```sql
INSERT INTO sym_router (
    router_id, source_node_group_id, target_node_group_id,
    router_type, create_time, last_update_time
) VALUES (
    'rt_server_to_client', 'server', 'client',
    'default', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

---

## ➤ Create Trigger (All Tables)

```sql
INSERT INTO sym_trigger (
    trigger_id, source_schema_name, source_table_name, channel_id,
    reload_channel_id, sync_on_insert, sync_on_update, sync_on_delete,
    sync_on_incoming_batch, use_stream_lobs, use_capture_lobs,
    use_capture_old_data, use_handle_key_updates, create_time, last_update_time
) VALUES (
    'trg_all_tables', 'public', '*', 'default',
    'reload', 1, 1, 1,
    0, 0, 0,
    1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

---

## ➤ Link Trigger with Router

```sql
INSERT INTO sym_trigger_router (
    trigger_id, router_id, initial_load_order, create_time, last_update_time
) VALUES (
    'trg_all_tables', 'rt_server_to_client', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

---

# 🔄 Step 6: Initial Sync

```bash
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001
```

Verify node:

```bash
docker exec -it db_server psql -U postgres -d serverdb \
  -c "SELECT node_id, node_group_id, sync_enabled FROM sym_node;"
```

---

# 🧪 Step 7: Testing Sync

## Create Table on Server

```sql
CREATE TABLE public.test_sync (
  id SERIAL PRIMARY KEY,
  name TEXT
);
```

## Insert Data

```sql
INSERT INTO public.test_sync (name) VALUES ('Hello from server');
```

## Verify on Client

```bash
docker exec -it db_client psql -U postgres -d clientdb -c "SELECT * FROM public.test_sync;"
```

---

# 🔁 Step 8: Reload / Resync

```bash
docker exec -it symmetricds_server bin/symadmin --engine server sync-triggers
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001
```

---

# 🔄 Step 9: Enable Bidirectional Sync

## ➤ Router (Client → Server)

```sql
INSERT INTO sym_router (
    router_id, source_node_group_id, target_node_group_id,
    router_type, create_time, last_update_time
) VALUES (
    'rt_client_to_server', 'client', 'server',
    'default', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

---

## ➤ Link Trigger

```sql
INSERT INTO sym_trigger_router (
    trigger_id, router_id, initial_load_order, create_time, last_update_time
) VALUES (
    'trg_all_tables', 'rt_client_to_server', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

---

## ➤ Enable Node Communication

```sql
INSERT INTO sym_node_group_link (
    source_node_group_id, target_node_group_id, data_event_action
) VALUES ('server', 'client', 'W')
ON CONFLICT DO NOTHING;

INSERT INTO sym_node_group_link (
    source_node_group_id, target_node_group_id, data_event_action
) VALUES ('client', 'server', 'W')
ON CONFLICT DO NOTHING;
```

---

## 🔄 Apply Changes

```bash
docker exec -it symmetricds_server bin/symadmin --engine server sync-triggers
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 000
```

---

# 🧩 Step 10: Sequence Fix (IMPORTANT)

👉 Prevents ID conflicts in bidirectional sync

```sql
DO $$
DECLARE
    rec RECORD;
    seq_name text;
    max_id bigint;
BEGIN
    FOR rec IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'id'
          AND data_type IN ('integer', 'bigint')
    LOOP
        seq_name := rec.table_name || '_' || rec.column_name || '_seq';

        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I;', seq_name);

        EXECUTE format(
            'ALTER TABLE %I ALTER COLUMN %I SET DEFAULT nextval(''%I'');',
            rec.table_name, rec.column_name, seq_name
        );

        EXECUTE format(
            'SELECT COALESCE(MAX(%I), 0) FROM %I;',
            rec.column_name, rec.table_name
        ) INTO max_id;

        IF max_id < 1 THEN
            max_id := 1;
        END IF;

        EXECUTE format(
            'SELECT setval(''%I'', %s, true);',
            seq_name, max_id
        );
    END LOOP;
END
$$;
```

---

# ⚠️ Important Notes

* Always run `sync-triggers` after config changes
* Use `reload-node` for full re-sync
* Writes can happen on both DBs after bidirectional setup
* Sequence sync is critical to avoid duplicate IDs

---

# 🎯 Final Outcome

✅ Real-time sync
✅ Bidirectional communication
✅ Load distribution
✅ Failover-ready system

---

# 🚀 Next Upgrade Ideas

* Add **Kafka** for async processing
* Deploy on **Kubernetes (StatefulSet)**
* Add **Monitoring (Prometheus + Grafana)**

---

# 🧾 Summary (One Line)

👉 “This setup ensures real-time bidirectional data synchronization between two PostgreSQL databases using SymmetricDS with high availability and conflict-safe sequence handling.”

---
