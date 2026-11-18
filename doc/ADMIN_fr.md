L'app doit être installée à la racine d'un domaine dédié : le frontend code en dur l'URL de base `/api`, les installations sous-sous-dossier ne fonctionnent pas.

L'inscription est désactivée à l'installation. Pour créer d'autres comptes, voir le README de l'app ou l'API (`POST /api/register`).

Les notifications partent via le Postfix de la machine, expéditeur `domain-watchdog@<domaine-d-install>`.

Redis tourne en serveur privé (`<app>-redis.service`), le consumer de la file de messages dans `<app>-worker.service` ; une troisième unité (`<app>-scheduler.service`) déclenche le traitement des watchlists toutes les 5 minutes, comme le déploiement amont. Logs dans le journal systemd (`journalctl -u <app>-worker`).
