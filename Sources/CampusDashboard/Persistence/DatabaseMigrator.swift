import Foundation

enum DatabaseMigrator {
    static func migrate(_ database: SQLiteDatabase) throws {
        let version = try database.scalarInt("PRAGMA user_version")
        guard version <= SQLiteDatabase.currentSchemaVersion else {
            throw DatabaseError.migration(expected: SQLiteDatabase.currentSchemaVersion, actual: version)
        }

        if version < 1 {
            try database.transaction {
                for statement in version1Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 1")
            }
        }

        if version < 2 {
            try database.transaction {
                for statement in version2Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 2")
            }
        }

        if version < 3 {
            try database.transaction {
                for statement in version3Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 3")
            }
        }

        if version < 4 {
            try database.transaction {
                for statement in version4Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 4")
            }
        }

        if version < 5 {
            try database.transaction {
                for statement in version5Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 5")
            }
        }

        if version < 6 {
            try database.transaction {
                for statement in version6Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 6")
            }
        }

        if version < 7 {
            try database.transaction {
                for statement in version7Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 7")
            }
        }

        if version < 8 {
            try database.transaction {
                for statement in version8Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 8")
            }
        }

        if version < 9 {
            try database.transaction {
                for statement in version9Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 9")
            }
        }

        if version < 10 {
            try database.transaction {
                for statement in version10Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 10")
            }
        }
        if version < 11 {
            try database.transaction {
                for statement in version11Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 11")
            }
        }
        if version < 12 {
            try database.transaction {
                for statement in version12Statements { try database.execute(statement) }
                try database.execute("PRAGMA user_version = 12")
            }
        }

        let finalVersion = try database.scalarInt("PRAGMA user_version")
        guard finalVersion == SQLiteDatabase.currentSchemaVersion else {
            throw DatabaseError.migration(expected: SQLiteDatabase.currentSchemaVersion, actual: finalVersion)
        }
    }

    private static let version12Statements = [
        """
        CREATE TABLE release_metric_events (
            id TEXT PRIMARY KEY,
            metric_kind TEXT NOT NULL,
            category TEXT NOT NULL,
            numeric_value REAL NOT NULL,
            occurred_at REAL NOT NULL
        )
        """,
        "CREATE INDEX idx_release_metric_events_kind_time ON release_metric_events(metric_kind, occurred_at)",
        """
        CREATE TABLE academic_analysis_decisions (
            analysis_id TEXT PRIMARY KEY REFERENCES academic_signal_analyses(id) ON DELETE CASCADE,
            decision_state TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """
    ]

    private static let version1Statements = [
        """
        CREATE TABLE source_accounts (
            id TEXT PRIMARY KEY,
            source_kind TEXT NOT NULL,
            instance_url TEXT NOT NULL,
            display_name TEXT NOT NULL,
            authorization_state TEXT NOT NULL,
            capabilities_json TEXT NOT NULL DEFAULT '{}',
            last_successful_sync REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(source_kind, instance_url)
        )
        """,
        """
        CREATE TABLE raw_source_records (
            id TEXT PRIMARY KEY,
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            object_type TEXT NOT NULL,
            source_object_id TEXT NOT NULL,
            fetch_batch_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            payload BLOB NOT NULL,
            fetched_at REAL NOT NULL,
            UNIQUE(source_account_id, object_type, source_object_id, content_hash)
        )
        """,
        """
        CREATE TABLE courses (
            id TEXT PRIMARY KEY,
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            source_object_id TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT NOT NULL,
            term TEXT NOT NULL,
            time_zone TEXT NOT NULL,
            source_url TEXT,
            source_state TEXT NOT NULL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            source_updated_at REAL,
            UNIQUE(source_account_id, source_object_id)
        )
        """,
        """
        CREATE TABLE course_meetings (
            id TEXT PRIMARY KEY,
            course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            source_object_id TEXT NOT NULL,
            starts_at REAL NOT NULL,
            ends_at REAL NOT NULL,
            is_all_day INTEGER NOT NULL DEFAULT 0,
            original_time_zone TEXT NOT NULL,
            location TEXT NOT NULL,
            recurrence_rule TEXT,
            source_state TEXT NOT NULL,
            source_updated_at REAL,
            UNIQUE(course_id, source_object_id)
        )
        """,
        """
        CREATE TABLE learning_tasks (
            id TEXT PRIMARY KEY,
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            source_object_id TEXT NOT NULL,
            course_id TEXT REFERENCES courses(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            official_type TEXT NOT NULL,
            normalized_type TEXT,
            official_due_at REAL,
            official_due_time_zone TEXT,
            official_due_is_all_day INTEGER NOT NULL DEFAULT 0,
            suggested_complete_at REAL,
            suggestion_origin TEXT,
            suggestion_confirmed_at REAL,
            opens_at REAL,
            locks_at REAL,
            source_url TEXT,
            source_state TEXT NOT NULL,
            source_updated_at REAL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            UNIQUE(source_account_id, source_object_id)
        )
        """,
        """
        CREATE TABLE announcements (
            id TEXT PRIMARY KEY,
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            source_object_id TEXT NOT NULL,
            course_id TEXT REFERENCES courses(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            published_at REAL NOT NULL,
            source_updated_at REAL,
            summary TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            source_url TEXT,
            source_state TEXT NOT NULL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            UNIQUE(source_account_id, source_object_id)
        )
        """,
        """
        CREATE TABLE local_user_states (
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            is_complete INTEGER NOT NULL DEFAULT 0,
            is_read INTEGER NOT NULL DEFAULT 0,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            priority TEXT,
            modified_at REAL NOT NULL,
            PRIMARY KEY(object_type, object_id)
        )
        """,
        """
        CREATE TABLE sync_runs (
            id TEXT PRIMARY KEY,
            trigger_kind TEXT NOT NULL,
            source_account_id TEXT REFERENCES source_accounts(id) ON DELETE SET NULL,
            fetch_state TEXT NOT NULL,
            normalize_state TEXT NOT NULL,
            persistence_state TEXT NOT NULL,
            read_count INTEGER NOT NULL DEFAULT 0,
            inserted_count INTEGER NOT NULL DEFAULT 0,
            updated_count INTEGER NOT NULL DEFAULT 0,
            cancelled_count INTEGER NOT NULL DEFAULT 0,
            started_at REAL NOT NULL,
            finished_at REAL,
            error_category TEXT,
            redacted_error_summary TEXT
        )
        """,
        """
        CREATE TABLE change_records (
            id TEXT PRIMARY KEY,
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            field_name TEXT NOT NULL,
            old_value_summary TEXT,
            new_value_summary TEXT,
            change_source TEXT NOT NULL,
            discovered_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE calendar_bindings (
            id TEXT PRIMARY KEY,
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            event_identifier TEXT NOT NULL,
            external_event_identifier TEXT,
            ownership_marker TEXT NOT NULL,
            calendar_identifier TEXT NOT NULL,
            calendar_source_identifier TEXT NOT NULL,
            sync_state TEXT NOT NULL,
            last_verified_at REAL,
            UNIQUE(object_type, object_id)
        )
        """,
        """
        CREATE TABLE notification_deliveries (
            notification_key TEXT PRIMARY KEY,
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            notification_type TEXT NOT NULL,
            scheduled_at REAL NOT NULL,
            state TEXT NOT NULL,
            system_notification_id TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE ai_parse_results (
            id TEXT PRIMARY KEY,
            raw_source_record_id TEXT NOT NULL REFERENCES raw_source_records(id) ON DELETE CASCADE,
            input_hash TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            suggested_type TEXT,
            normalized_title TEXT,
            official_date_echo REAL,
            suggested_date REAL,
            confidence REAL NOT NULL,
            rationale TEXT NOT NULL,
            has_conflict INTEGER NOT NULL DEFAULT 0,
            confirmation_state TEXT NOT NULL,
            created_at REAL NOT NULL,
            UNIQUE(raw_source_record_id, input_hash, model, prompt_version, schema_version)
        )
        """,
        """
        CREATE TABLE outbox_work (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            deduplication_key TEXT NOT NULL UNIQUE,
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            payload BLOB NOT NULL,
            state TEXT NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            available_at REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_error_category TEXT
        )
        """,
        "CREATE INDEX idx_outbox_ready ON outbox_work(state, available_at)",
        "CREATE INDEX idx_raw_source_identity ON raw_source_records(source_account_id, object_type, source_object_id)",
        "CREATE INDEX idx_tasks_due ON learning_tasks(official_due_at)",
        "CREATE INDEX idx_announcements_published ON announcements(published_at)"
    ]

    private static let version2Statements = [
        """
        CREATE TABLE source_presence (
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            object_type TEXT NOT NULL,
            source_object_id TEXT NOT NULL,
            consecutive_complete_absences INTEGER NOT NULL DEFAULT 0,
            last_observed_run_id TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY(source_account_id, object_type, source_object_id)
        )
        """,
        "CREATE INDEX idx_source_presence_absence ON source_presence(source_account_id, object_type, consecutive_complete_absences)"
    ]

    private static let version3Statements = [
        """
        CREATE TABLE source_baselines (
            source_account_id TEXT NOT NULL REFERENCES source_accounts(id) ON DELETE CASCADE,
            object_type TEXT NOT NULL,
            completed_run_id TEXT NOT NULL,
            completed_at REAL NOT NULL,
            PRIMARY KEY(source_account_id, object_type)
        )
        """
    ]

    private static let version4Statements = [
        """
        CREATE TABLE managed_calendar_identity (
            singleton_key INTEGER PRIMARY KEY CHECK(singleton_key = 1),
            internal_id TEXT NOT NULL,
            calendar_identifier TEXT NOT NULL,
            source_identifier TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            source_title TEXT NOT NULL,
            calendar_title TEXT NOT NULL,
            selection_kind TEXT NOT NULL,
            ownership_marker TEXT NOT NULL UNIQUE,
            validation_state TEXT NOT NULL,
            last_verified_at REAL
        )
        """
    ]

    private static let version5Statements = [
        """
        CREATE TABLE notification_preferences (
            singleton_key INTEGER PRIMARY KEY CHECK(singleton_key = 1),
            enabled INTEGER NOT NULL DEFAULT 0,
            deadline_offsets_minutes TEXT NOT NULL DEFAULT '1440,180,60',
            class_lead_minutes INTEGER NOT NULL DEFAULT 15,
            quiet_start_minutes INTEGER NOT NULL DEFAULT 1320,
            quiet_end_minutes INTEGER NOT NULL DEFAULT 480,
            policy_version INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE course_notification_preferences (
            course_id TEXT PRIMARY KEY REFERENCES courses(id) ON DELETE CASCADE,
            enabled INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE sync_notification_state (
            source_account_id TEXT PRIMARY KEY REFERENCES source_accounts(id) ON DELETE CASCADE,
            failure_active INTEGER NOT NULL DEFAULT 0,
            failure_notification_emitted INTEGER NOT NULL DEFAULT 0,
            recovery_notification_emitted INTEGER NOT NULL DEFAULT 0,
            last_error_category TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE background_schedule_state (
            singleton_key INTEGER PRIMARY KEY CHECK(singleton_key = 1),
            enabled INTEGER NOT NULL DEFAULT 0,
            target_interval_seconds REAL NOT NULL DEFAULT 3600,
            last_attempt_at REAL,
            last_completed_at REAL,
            last_trigger TEXT,
            last_result TEXT,
            last_error_category TEXT,
            updated_at REAL NOT NULL
        )
        """,
        "INSERT INTO notification_preferences(singleton_key, updated_at) VALUES (1, 0)",
        "INSERT INTO background_schedule_state(singleton_key, updated_at) VALUES (1, 0)"
    ]

    private static let version6Statements = [
        "ALTER TABLE sync_notification_state ADD COLUMN failure_cycle INTEGER NOT NULL DEFAULT 0"
    ]

    private static let version7Statements = [
        "ALTER TABLE ai_parse_results ADD COLUMN target_object_type TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN target_object_id TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN related_object_ids_json TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE ai_parse_results ADD COLUMN action_items_json TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE ai_parse_results ADD COLUMN suggested_date_origin TEXT NOT NULL DEFAULT 'inferred'",
        "ALTER TABLE ai_parse_results ADD COLUMN change_summary TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE ai_parse_results ADD COLUMN output_json BLOB",
        "ALTER TABLE ai_parse_results ADD COLUMN failure_category TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN adopted_normalized_title TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN adopted_type TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN adopted_date REAL",
        "ALTER TABLE ai_parse_results ADD COLUMN source_summary TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE ai_parse_results ADD COLUMN source_url TEXT",
        "ALTER TABLE ai_parse_results ADD COLUMN updated_at REAL NOT NULL DEFAULT 0",
        "CREATE INDEX idx_ai_confirmation_queue ON ai_parse_results(confirmation_state, created_at)",
        """
        CREATE TABLE ai_settings (
            singleton_key INTEGER PRIMARY KEY CHECK(singleton_key = 1),
            enabled INTEGER NOT NULL DEFAULT 0,
            provider_kind TEXT NOT NULL DEFAULT 'deterministic_fake',
            provider_disclosure TEXT,
            transmitted_fields TEXT,
            retention_policy TEXT,
            consented_at REAL,
            updated_at REAL NOT NULL
        )
        """,
        "INSERT INTO ai_settings(singleton_key, updated_at) VALUES (1, 0)",
        """
        CREATE TABLE ai_confirmation_audit (
            id TEXT PRIMARY KEY,
            parse_result_id TEXT NOT NULL REFERENCES ai_parse_results(id) ON DELETE CASCADE,
            action TEXT NOT NULL,
            previous_state TEXT NOT NULL,
            new_state TEXT NOT NULL,
            correction_json TEXT,
            occurred_at REAL NOT NULL
        )
        """,
        "CREATE INDEX idx_ai_audit_result ON ai_confirmation_audit(parse_result_id, occurred_at)",
        """
        CREATE TABLE ai_applied_values (
            parse_result_id TEXT PRIMARY KEY REFERENCES ai_parse_results(id) ON DELETE CASCADE,
            previous_normalized_type TEXT,
            previous_suggested_complete_at REAL,
            previous_suggestion_origin TEXT,
            previous_suggestion_confirmed_at REAL,
            applied_at REAL NOT NULL,
            restored_at REAL
        )
        """
    ]

    private static let version8Statements = [
        "ALTER TABLE ai_settings ADD COLUMN consent_version TEXT",
        "ALTER TABLE ai_settings ADD COLUMN consent_signature TEXT",
        "ALTER TABLE ai_settings ADD COLUMN school_policy_confirmed INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE ai_settings ADD COLUMN provider_model TEXT",
        "ALTER TABLE ai_settings ADD COLUMN per_run_request_budget INTEGER NOT NULL DEFAULT 10",
        "ALTER TABLE ai_settings ADD COLUMN daily_request_budget INTEGER NOT NULL DEFAULT 50",
        "ALTER TABLE ai_settings ADD COLUMN per_run_token_budget INTEGER NOT NULL DEFAULT 20000",
        "ALTER TABLE ai_settings ADD COLUMN daily_token_budget INTEGER NOT NULL DEFAULT 100000",
        "UPDATE ai_settings SET enabled=0, provider_kind='external', consented_at=NULL, consent_version=NULL, consent_signature=NULL, school_policy_confirmed=0, provider_model='deepseek-v4-flash' WHERE singleton_key=1",
        """
        CREATE TABLE ai_provider_cache (
            cache_key TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            response_json BLOB NOT NULL,
            input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            created_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE ai_provider_usage (
            day_key TEXT PRIMARY KEY,
            request_count INTEGER NOT NULL DEFAULT 0,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            estimated_cost_microusd INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        )
        """
    ]

    private static let version9Statements = [
        "ALTER TABLE ai_settings ADD COLUMN deepseek_direct_https INTEGER NOT NULL DEFAULT 0"
    ]

    private static let version10Statements = [
        """
        CREATE TABLE academic_signal_analyses (
            id TEXT PRIMARY KEY,
            raw_source_record_id TEXT NOT NULL REFERENCES raw_source_records(id) ON DELETE CASCADE,
            announcement_id TEXT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
            source_account_id TEXT NOT NULL,
            source_object_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            primary_category TEXT NOT NULL,
            status TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            failure_category TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(raw_source_record_id,content_hash,provider,model,prompt_version,schema_version)
        )
        """,
        "CREATE INDEX idx_academic_analysis_announcement ON academic_signal_analyses(announcement_id,created_at)",
        """
        CREATE TABLE academic_signals (
            id TEXT PRIMARY KEY,
            analysis_id TEXT NOT NULL REFERENCES academic_signal_analyses(id) ON DELETE CASCADE,
            announcement_id TEXT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
            source_account_id TEXT NOT NULL,
            source_object_id TEXT NOT NULL,
            category TEXT NOT NULL,
            evidence TEXT NOT NULL,
            key_requirement TEXT NOT NULL,
            inferred_date REAL,
            is_all_day INTEGER NOT NULL DEFAULT 0,
            time_zone_identifier TEXT,
            confidence REAL NOT NULL,
            reason TEXT NOT NULL,
            conflicts_json TEXT NOT NULL DEFAULT '[]',
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            confirmation_state TEXT NOT NULL,
            adopted_category TEXT,
            adopted_date REAL,
            adopted_is_all_day INTEGER,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX idx_academic_signal_active ON academic_signals(is_active,confirmation_state,created_at)",
        """
        CREATE TABLE academic_signal_audit (
            id TEXT PRIMARY KEY,
            signal_id TEXT NOT NULL REFERENCES academic_signals(id) ON DELETE CASCADE,
            action TEXT NOT NULL,
            previous_state TEXT NOT NULL,
            new_state TEXT NOT NULL,
            correction_json BLOB,
            occurred_at REAL NOT NULL
        )
        """,
        "CREATE INDEX idx_academic_signal_audit ON academic_signal_audit(signal_id,occurred_at)"
    ]

    private static let version11Statements = [
        "ALTER TABLE academic_signals ADD COLUMN course_id TEXT REFERENCES courses(id) ON DELETE SET NULL",
        "ALTER TABLE academic_signals ADD COLUMN adopted_key_requirement TEXT",
        "ALTER TABLE academic_signals ADD COLUMN adopted_time_zone_identifier TEXT",
        "ALTER TABLE academic_signals ADD COLUMN decision_origin TEXT NOT NULL DEFAULT 'automated'",
        "ALTER TABLE academic_signals ADD COLUMN personalization_rule_version TEXT",
        "ALTER TABLE academic_signals ADD COLUMN target_meeting_id TEXT REFERENCES course_meetings(id) ON DELETE SET NULL",
        "ALTER TABLE academic_signals ADD COLUMN audience_resolution TEXT NOT NULL DEFAULT 'no_target'",
        "CREATE INDEX idx_academic_signal_analysis_decision ON academic_signals(analysis_id,decision_origin,is_active)",
        """
        CREATE TABLE academic_personalization_rules (
            id TEXT PRIMARY KEY,
            course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            trigger_phrase TEXT NOT NULL,
            category TEXT NOT NULL,
            key_requirement TEXT NOT NULL,
            rule_version TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(course_id,trigger_phrase,rule_version)
        )
        """,
        """
        CREATE TABLE academic_course_mappings (
            id TEXT PRIMARY KEY,
            canvas_course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            siweb_course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            section_key TEXT,
            origin TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(canvas_course_id,siweb_course_id,section_key)
        )
        """
    ]
}
