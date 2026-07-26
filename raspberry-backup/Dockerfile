FROM python:3.12-alpine

WORKDIR /app
COPY server.py .

ENV BACKUP_DATA_DIR=/data
ENV BACKUP_PORT=8787
ENV BACKUP_RETENTION_DAYS=30

VOLUME ["/data"]
EXPOSE 8787

CMD ["python", "-u", "server.py"]
