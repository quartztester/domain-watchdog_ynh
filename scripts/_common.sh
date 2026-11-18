#!/bin/bash

#=================================================
# GENERIC FINALIZATION FOR DOMAIN WATCHDOG
#=================================================

_domain_watchdog_console() {
    # Run bin/console as the app user with the app env file loaded.
    # Symfony logs deprecations to stderr; the CI counts stderr lines as
    # warnings and aborts the test on the flood, so merge them into stdout.
    ynh_exec_as_app env "APP_ENV=prod" bash -c "cd '$install_dir' && php$php_version bin/console $*" 2>&1 || return 1
}

_domain_watchdog_composer_install() {
    composer_version="2.11.2" ynh_composer_install
    # Loud build steps spam stderr: YunoHost counts each line as a warning
    # and the CI aborts the test on the flood. Build quietly.
    composer_user="$app" ynh_composer_exec install --no-dev --no-scripts --no-progress --quiet 2>&1 >/dev/null
}

_domain_watchdog_yarn_build() {
    # node 22 provides corepack; the yarn.lock is yarn-1 format, pin classic
    ynh_exec_as_app env HOME="$install_dir" PATH="$path_with_nodejs:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 bash -c \
        "cd '$install_dir' && corepack yarn@1 install --frozen-lockfile --silent --non-interactive && corepack yarn@1 run --silent build && corepack yarn@1 run --silent ttag:po2json" >/dev/null 2>&1
    _domain_watchdog_console "assets:install public" >/dev/null 2>&1
    rm -rf "$install_dir/node_modules"
}

_domain_watchdog_build_prod_env() {
    # Compile .env.local into .env.local.php, refresh the autoloader and warm
    # the prod cache without re-running symfony-cmd auto-scripts (network)
    ynh_exec_as_app env HOME="$install_dir" PATH="$path_with_nodejs:$PATH" bash -c \
        "cd '$install_dir' && php$php_version composer.phar dump-env prod && php$php_version composer.phar dump-autoload --classmap-authoritative --no-dev --quiet && php$php_version bin/console cache:warmup --no-interaction -q" >/dev/null 2>&1
}

_domain_watchdog_create_admin_user() {
    local email="$1" password="$2"

    # The app's 'auto' hasher is PHP's native bcrypt; hash without booting Symfony
    local hash
    hash=$(DW_PW="$password" "php$php_version" -r 'echo password_hash(getenv("DW_PW"), PASSWORD_DEFAULT);') \
        || ynh_die "Unable to hash the admin password"

    # ON CONFLICT keeps this idempotent across upgrades and restores;
    # unquoted heredoc so $hash ($2y$...) is not re-interpolated
    ynh_psql_db_shell "$db_name" <<SQL
INSERT INTO "user" (id, email, roles, password, created_at, verified_at) VALUES (nextval('user_id_seq'), '$email', '["ROLE_USER"]', '$hash', NOW(), NOW()) ON CONFLICT (email) DO NOTHING;
SQL
}

#=================================================
# SYSTEMD SERVICES
#=================================================

_add_domain_watchdog_units() {
    ynh_config_add_systemd --service="${app}-redis" --template=redis.service
    ynh_config_add_systemd --service="${app}-worker" --template=worker.service
    ynh_config_add_systemd --service="${app}-scheduler" --template=scheduler.service
}

_start_domain_watchdog_services() {
    ynh_systemctl --service="${app}-redis" --action=start
    ynh_systemctl --service="${app}-worker" --action=start
    ynh_systemctl --service="${app}-scheduler" --action=start
}

# In install, start units one at a time so the worker's startup line can be
# watched: a double start (helper then wait_until) races the journal tail.
_start_domain_watchdog_services_with_worker_gate() {
    ynh_systemctl --service="${app}-redis" --action=start
    ynh_systemctl --service="${app}-worker" --action=start --wait_until="Consuming" --log_path=systemd --timeout=120
    ynh_systemctl --service="${app}-scheduler" --action=start
}

_stop_domain_watchdog_services() {
    for svc in scheduler worker redis; do
        ynh_systemctl --service="${app}-${svc}" --action=stop || true
    done
}

_remove_domain_watchdog_units() {
    _stop_domain_watchdog_services
    ynh_config_remove_systemd "${app}-scheduler"
    ynh_config_remove_systemd "${app}-worker"
    ynh_config_remove_systemd "${app}-redis"
}
