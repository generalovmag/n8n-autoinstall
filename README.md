````md
# n8n Auto-Install (Ubuntu + Docker)

Установка n8n одной командой. Скрипт ставит Docker, поднимает n8n + PostgreSQL, настраивает Traefik с TLS (по домену), UFW и бэкап.

---

## Содержание
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Что делает установщик](#что-делает-установщик)
- [Доступ после установки](#доступ-после-установки)
- [Настройка после входа](#настройка-после-входа)
- [Где лежат данные](#где-лежат-данные)
- [Администрирование](#администрирование)
- [Обновление версии n8n](#обновление-версии-n8n)
- [Восстановление из бэкапа](#восстановление-из-бэкапа)
- [Переменные окружения](#переменные-окружения)
- [DNS и TLS](#dns-и-tls)
- [Порты и файрвол](#порты-и-файрвол)
- [Безопасность](#безопасность)
- [Частые проблемы](#частые-проблемы)
- [Проверка целостности скрипта](#проверка-целостности-скрипта)
- [Лицензия](#лицензия)

---

## Требования
- **ОС:** Ubuntu 22.04/24.04 с `apt`.
- **Доступ:** root (`ssh root@IP` или `sudo -i`).
- **Ресурсы:** ≥1 vCPU и 1 ГБ ОЗУ (рекомендовано 2 ГБ+), диск 10 ГБ+.
- **Сеть:** исходящий интернет разрешён.
- **Порты:** 22/tcp всегда; 80 и 443 при установке с доменом.
- **Домен (опционально):** A-запись домена → публичный IP сервера.

---

## Быстрый старт

**С доменом и TLS Let’s Encrypt**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/generalovmag/n8n-autoinstall/main/install_n8n.sh) \
  --domain your.domain --email you@example.com
````

**Без домена (доступ через SSH-туннель)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/generalovmag/n8n-autoinstall/main/install_n8n.sh) --no-domain
```

> В конце установки выводятся URL и данные Basic Auth.

---

## Что делает установщик

* Ставит Docker Engine и compose-plugin.
* Создаёт каталоги: `/opt/n8n/{data,db,backups,proxy}`.
* Разворачивает **PostgreSQL 16** и **n8n** в Docker.
* При домене включает **Traefik** + Let’s Encrypt.
* Включает UFW и открывает нужные порты.
* Включает Basic Auth (логин `n8n`, пароль генерируется).
* Генерирует `N8N_ENCRYPTION_KEY`.
* Ежедневный бэкап БД в 02:17, хранение 7 дней.
* Таймзона по умолчанию `Europe/Moscow`.

---

## Доступ после установки

### Если указан домен

1. Открой `https://your.domain`.
2. Введи Basic Auth → создай учётку Owner в n8n.

### Если домена нет

1. На своём ПК создай туннель:

   ```bash
   ssh -N -L 5678:127.0.0.1:5678 root@<SERVER_IP>
   ```
2. Открой `http://127.0.0.1:5678`.
3. Введи Basic Auth → создай учётку Owner.

**Добавить домен позже**

```bash
# после создания A-записи домена на IP сервера
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) \
  --domain your.domain --email you@example.com --non-interactive
```

---

## Настройка после входа

* **SMTP:** `Settings → Email → SMTP` в UI n8n.
* **Вебхуки:** при HTTPS `WEBHOOK_URL` задан. Локально тестируй через туннель.
* **Часовой пояс:** по умолчанию `Europe/Moscow`.

---

## Где лежат данные

* Конфиг и данные n8n: `/opt/n8n/data`
* Данные PostgreSQL: `/opt/n8n/db`
* Бэкапы БД: `/opt/n8n/backups`
* Compose-файл: `/opt/n8n/docker-compose.yml`
* Скрипт бэкапа: `/usr/local/bin/n8n_pg_backup.sh`

---

## Администрирование

```bash
# обновить до версии из .env
cd /opt/n8n && docker compose pull && docker compose up -d

# логи n8n
cd /opt/n8n && docker compose logs -f --tail=200 n8n

# бэкап вручную
/usr/local/bin/n8n_pg_backup.sh

# остановить сервисы
cd /opt/n8n && docker compose down

# полный снос с данными
cd /opt/n8n && docker compose down -v && rm -rf /opt/n8n
```

---

## Обновление версии n8n

1. Открой `/opt/n8n/.env` и измени `N8N_VERSION` на нужный тег.
2. Применяй:

   ```bash
   cd /opt/n8n && docker compose pull && docker compose up -d
   ```

---

## Восстановление из бэкапа

```bash
cd /opt/n8n && docker compose down                # остановить
cd /opt/n8n && docker compose up -d db            # поднять только БД
gunzip -c /opt/n8n/backups/pg_YYYY-MM-DD_HH-MM-SS.sql.gz | \
  docker compose exec -T db psql -U n8n -d n8n    # восстановить дамп
cd /opt/n8n && docker compose up -d               # запустить всё
```

---

## Переменные окружения

Можно передать при запуске установщика:

* `N8N_VERSION` — тег образа n8n (по умолчанию `1.64.0`)
* `TZ` — таймзона (по умолчанию `Europe/Moscow`)
* `BACKUP_RETENTION_DAYS` — дни хранения бэкапов (по умолчанию `7`)
* `N8N_BASIC_AUTH_USER`, `N8N_BASIC_AUTH_PASSWORD`
* `POSTGRES_PASSWORD`

**Пример**

```bash
N8N_VERSION=1.64.0 TZ=Europe/Berlin \
bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) \
  --domain your.domain --email you@example.com
```

---

## DNS и TLS

* Создай A-запись `@` или `n8n` → публичный IP сервера.
* Дождись применения DNS.
* Убедись, что 80/443 доступны извне.
* Traefik автоматически выпустит и продлит сертификаты Let’s Encrypt.

---

## Порты и файрвол

* UFW включается автоматически.
* Открытые порты:

  * всегда: `22/tcp`
  * при домене: `80/tcp`, `443/tcp`
* Если 80/443 заняты Nginx/Apache — останови их перед установкой.

---

## Безопасность

* Сразу замени пароль Basic Auth.
* Храни секреты вне публичных репозиториев.
* Ограничь доступ по SSH-ключам, отключи лишние учётки.
* Регулярно проверяй бэкапы и тестируй восстановление.

---

## Частые проблемы

* **Нет сертификата / 404:** проверь A-запись и доступность 80/443; смотри `docker compose logs traefik`.
* **Порт занят:** проверь `ss -ltnp | grep -E ':80|:443|:5678'`, освободи и перезапусти.
* **Мало памяти:** нужно ≥2 ГБ ОЗУ для стабильной работы.
* **Не root:** выполни `sudo -i` и запусти установку заново.

---

## Проверка целостности скрипта

(если опубликован хеш)

```bash
curl -fsSLO https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh{,.sha256}
sha256sum -c install_n8n.sh.sha256 && sudo bash install_n8n.sh --no-domain
```


```
```
