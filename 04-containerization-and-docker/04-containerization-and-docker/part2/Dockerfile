FROM python:3.11-alpine

WORKDIR /app

COPY ../app /app

RUN pip install --no-cache-dir flask

CMD ["python", "app.py"]
