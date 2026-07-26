# Бэкап на Raspberry Pi

Второй канал рядом с Firebase: JSON уходит на домашний сервер в Docker.

## На Pi

```bash
cd raspberry-backup
cp .env.example .env
# задай длинный BACKUP_TOKEN в .env
docker compose up -d --build
curl http://127.0.0.1:8787/health
```

- Порт: **8787**
- Файлы: `data/latest.json` и `data/archive/backup-YYYY-MM-DD.json` (хранятся 30 дней)
- В роутере закрепи постоянный IP малинки

## В приложении (Профиль → RASPBERRY PI)

| Поле | Пример |
|------|--------|
| LAN URL | `http://192.168.10.30:8787` |
| Tailscale URL | `http://100.99.85.87:8787` |
| Токен | тот же, что `BACKUP_TOKEN` |

Включи «Бэкап на Raspberry Pi».

## Как работает

1. **Авто (~03:00)** — сначала LAN, при ошибке Tailscale. iOS не гарантирует точное время; есть догон при открытии приложения, если прошло >24 ч.
2. **Если LAN и Tailscale недоступны** — локальное уведомление: проверь сеть / включи Tailscale и сделай бэкап вручную.
3. **Кнопка «Сохранить на Raspberry Pi»** — сначала LAN, при ошибке Tailscale URL.
4. Firebase-бэкап не отключается.

## Проверка

```bash
# с телефона в одной Wi‑Fi (или с другого устройства в LAN):
curl -H "Authorization: Bearer ТВОЙ_ТОКЕН" http://IP_PI:8787/health
```
