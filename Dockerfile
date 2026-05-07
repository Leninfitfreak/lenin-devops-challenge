FROM python:3.9.18-slim-bullseye

WORKDIR /app

RUN useradd -m appuser

COPY app/requirements.txt .
RUN pip install -r requirements.txt

COPY app/ /app/
RUN chown -R appuser:appuser /app

EXPOSE 80

CMD ["python", "main.py"]
