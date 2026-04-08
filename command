
docker-compose up -d
--------------------------------------------------------------------------------------
Open browser → http://localhost:5050
Login:
Email: admin@admin.com
Password: admin

Add new server:
Name: ServerDB
Host: db_server
Port: 5432
User: postgres
Password: postgres

Add another server for ClientDB:
Name: ClientDB
Host: db_client
Port: 5432
User: postgres
Password: postgres

--------------------------------------------------------------------------------------


docker exec -it db_server psql -U postgres -d serverdb


docker compose up -d symmetricds_server db_server
docker exec -it symmetricds_server bin/symadmin --engine server open-registration client 001
docker compose up -d symmetricds_client db_client

--------------------------------------------------------------------------------
-- On serverdb
INSERT INTO sym_router (
    router_id, source_node_group_id, target_node_group_id,
    router_type, create_time, last_update_time
) VALUES (
    'rt_server_to_client', 'server', 'client',
    'default', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);

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

INSERT INTO sym_trigger_router (
    trigger_id, router_id, initial_load_order, create_time, last_update_time
) VALUES (
    'trg_all_tables', 'rt_server_to_client', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);



docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001



docker exec -it db_server psql -U postgres -d serverdb \
  -c "SELECT node_id, node_group_id, sync_enabled FROM sym_node;"



-------------------------------------------------------------------------------------------

docker compose up -d pgadmin

# TEST
docker exec -it db_server psql -U postgres -d serverdb

CREATE TABLE public.test_sync (
  id SERIAL PRIMARY KEY,
  name TEXT
);

INSERT INTO public.test_sync (name) VALUES ('Hello from server');

docker exec -it db_client psql -U postgres -d clientdb -c "SELECT * FROM public.test_sync;"


----------------------------------------------------------------------------------------------------
RELOAD

docker exec -it symmetricds_server bin/symadmin --engine server sync-triggers
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001

---------------------------------------------------------------------------------------------------

SETTING UP Back Communitcation

-- Router for client → server
INSERT INTO sym_router (
    router_id, source_node_group_id, target_node_group_id,
    router_type, create_time, last_update_time
) VALUES (
    'rt_client_to_server', 'client', 'server',
    'default', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);


INSERT INTO sym_trigger_router (
    trigger_id, router_id, initial_load_order, create_time, last_update_time
) VALUES (
    'trg_all_tables', 'rt_client_to_server', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);


INSERT INTO sym_node_group_link (
    source_node_group_id, target_node_group_id, data_event_action
) VALUES
('server', 'client', 'W')
ON CONFLICT DO NOTHING;

INSERT INTO sym_node_group_link (
    source_node_group_id, target_node_group_id, data_event_action
) VALUES
('client', 'server', 'W')
ON CONFLICT DO NOTHING;


docker exec -it symmetricds_server bin/symadmin --engine server sync-triggers
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 001
docker exec -it symmetricds_server bin/symadmin --engine server reload-node 000




***********************************************************************************************

create_sequence_table




DO $$
DECLARE
    rec RECORD;
    seq_name text;
    max_id bigint;
BEGIN
    -- Loop over all tables in public schema
    FOR rec IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'id'
          AND data_type IN ('integer', 'bigint')
    LOOP
        seq_name := rec.table_name || '_' || rec.column_name || '_seq';

        -- Create sequence if not exists
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I;', seq_name);

        -- Set default to use sequence
        EXECUTE format(
            'ALTER TABLE %I ALTER COLUMN %I SET DEFAULT nextval(''%I'');',
            rec.table_name, rec.column_name, seq_name
        );

        -- Get max(id) of table
        EXECUTE format('SELECT COALESCE(MAX(%I), 0) FROM %I;', rec.column_name, rec.table_name)
        INTO max_id;

        -- If table empty, set sequence to 1, else max(id)
        IF max_id < 1 THEN
            max_id := 1;
        END IF;

        -- Sync sequence to max(id)
        EXECUTE format('SELECT setval(''%I'', %s, true);', seq_name, max_id);
    END LOOP;
END
$$;