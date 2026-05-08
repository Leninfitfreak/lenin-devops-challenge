FROM python:3.9.18-slim-bullseye AS builder

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

FROM python:3.9.18-slim-bullseye

WORKDIR /app

RUN groupadd -g 1000 appuser && useradd -u 1000 -g 1000 -m appuser

COPY --from=builder /install /usr/local

COPY app/ /app/
RUN chown -R 1000:1000 /app

EXPOSE 8080

USER 1000:1000

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--timeout", "30", "--graceful-timeout", "25", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "--error-logfile", "-", "main:app"]
