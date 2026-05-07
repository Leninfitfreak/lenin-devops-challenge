FROM python:3.9.18-slim-bullseye

WORKDIR /app

RUN useradd -m appuser

COPY app/requirements.txt .
RUN pip install -r requirements.txt

COPY app/ /app/
RUN chown -R appuser:appuser /app

EXPOSE 80

USER appuser

CMD ["gunicorn", "--bind", "0.0.0.0:80", "--workers", "1", "--timeout", "30", "--graceful-timeout", "25", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "--error-logfile", "-", "main:app"]
