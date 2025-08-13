n8n Auto-Install (Ubuntu + Docker)
Установка n8n в один шаг. Скрипт ставит Docker, поднимает n8n + PostgreSQL, настраивает прокси с TLS (опционально), файрвол и бэкап.

Быстрый старт
С доменом и TLS Let’s Encrypt

bash
Копировать
Редактировать
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) \
  --domain your.domain --email you@example.com
Без домена (доступ через SSH-туннель)

bash
Копировать
Редактировать
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) --no-domain
Вывод скрипта покажет URL и Basic Auth.

Требования
ОС: Ubuntu 22.04 или 24.04 с apt.

Доступ: root (ssh root@IP или sudo -i).

Интернет: исходящие соединения разрешены.

Ресурсы: минимум 1 vCPU и 1 ГБ ОЗУ, рекомендуем 2 ГБ+. Диск 10 ГБ+.

Порты:

всегда: 22/tcp,

с доменом: 80/tcp и 443/tcp должны быть свободны и открыты наружу.

Домен (опционально): A-запись домена → публичный IP сервера.

Что делает установщик
Ставит Docker Engine и compose-plugin.

Создаёт каталоги /opt/n8n/{data,db,backups,proxy}.

Разворачивает PostgreSQL 16 и n8n в Docker.

При указанном домене добавляет Traefik с автосертификатами Let’s Encrypt.

Включает UFW и разрешает нужные порты.

Включает Basic Auth для n8n (логин n8n, пароль генерируется).

Создаёт N8N_ENCRYPTION_KEY.

Ежедневный бэкап БД в 02:17 с хранением 7 дней.

Таймзона по умолчанию Europe/Moscow (можно изменить).

Доступ после установки
Если указан домен
Открой: https://your.domain

Введи Basic Auth (из вывода скрипта). Затем создай учётку Owner в n8n.

Если домена нет
На своём ПК открой SSH-туннель:

bash
Копировать
Редактировать
ssh -N -L 5678:127.0.0.1:5678 root@<SERVER_IP>
В браузере: http://127.0.0.1:5678

Введи Basic Auth. Создай учётку Owner.

Добавить домен позже
— Создай A-запись домена → IP сервера.
— Перезапусти установку:

bash
Копировать
Редактировать
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) \
  --domain your.domain --email you@example.com --non-interactive
Настройка после входа
SMTP: Settings → Email → SMTP в UI n8n. Введи параметры провайдера.

Вебхуки: при работе через HTTPS WEBHOOK_URL уже задан. При локальном доступе тестируй через туннель или прокси.

Часовой пояс: по умолчанию Europe/Moscow.

Где лежат данные
Конфиг и данные n8n: /opt/n8n/data

Данные PostgreSQL: /opt/n8n/db

Бэкапы БД: /opt/n8n/backups

Compose-файл: /opt/n8n/docker-compose.yml

Скрипт бэкапа: /usr/local/bin/n8n_pg_backup.sh

Администрирование
Обновить n8n до версии из .env:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose pull && docker compose up -d
Посмотреть логи:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose logs -f --tail=200 n8n
Сделать бэкап вручную:

bash
Копировать
Редактировать
/usr/local/bin/n8n_pg_backup.sh
Остановить сервисы:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose down
Полный снос с данными:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose down -v
rm -rf /opt/n8n
Обновление версии n8n
Открой /opt/n8n/.env, измени N8N_VERSION на нужный тег образа.

Применяй:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose pull && docker compose up -d
Откат аналогичный: выстави предыдущий тег и перезапусти.

Восстановление из бэкапа
Останови сервисы:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose down
Подними только БД:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose up -d db
Восстанови dump (замени файл на свой):

bash
Копировать
Редактировать
gunzip -c /opt/n8n/backups/pg_YYYY-MM-DD_HH-MM-SS.sql.gz | \
docker compose exec -T db psql -U n8n -d n8n
Запусти всё:

bash
Копировать
Редактировать
cd /opt/n8n && docker compose up -d
Переменные окружения (опционально при запуске установщика)
Можно передать до запуска:

N8N_VERSION — тег образа n8n, по умолчанию 1.64.0

TZ — таймзона, по умолчанию Europe/Moscow

BACKUP_RETENTION_DAYS — дни хранения бэкапов, по умолчанию 7

N8N_BASIC_AUTH_USER, N8N_BASIC_AUTH_PASSWORD

POSTGRES_PASSWORD

Пример:

bash
Копировать
Редактировать
N8N_VERSION=1.64.0 TZ=Europe/Berlin \
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) \
  --domain your.domain --email you@example.com
DNS и TLS (кратко)
A-запись @ или n8n → публичный IP сервера.

Подожди распространения DNS.

Убедись, что 80/443 открыты наружу.

Скрипт сам выпустит сертификат через Let’s Encrypt при первом запуске.

Порты и файрвол
UFW включается автоматически. Разрешено:

всегда: 22/tcp

при домене: 80/tcp, 443/tcp

Если стоят Nginx/Apache, освободите 80/443 перед установкой.

Безопасность
Сразу поменяй Basic Auth на свой.

Храни пароли вне публичных мест.

Отключи ненужные учётки на сервере.

Делай регулярные бэкапы. Тестируй восстановление.

Частые проблемы
Нет сертификата / 404: проверь A-запись и что 80/443 доступны извне; смотри логи docker compose logs traefik.

Порт занят: ss -ltnp | grep -E ':80|:443|:5678'. Отключи конфликтующий сервис и перезапусти.

Недостаточно памяти: добавь ОЗУ или своп. Для стабильной работы нужно 2 ГБ+.

Не root: запусти sudo -i и повтори.

Проверка целостности скрипта (опционально)
Релиз может содержать файл с хешем:

bash
Копировать
Редактировать
curl -fsSLO https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh{,.sha256}
sha256sum -c install_n8n.sh.sha256 && sudo bash install_n8n.sh --no-domain
