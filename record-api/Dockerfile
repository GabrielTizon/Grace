########################################
#  Record-API – Dockerfile (DEV)
########################################
FROM python:3.12-slim

WORKDIR /app

# ▸ libs de sistema para compilar psycopg2
RUN apt-get update && \
    apt-get install -y gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# ▸ primeiro copia só o requirements e instala (cache)
COPY src/requirements.txt ./requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ▸ agora copia todo o código-fonte
COPY src/ .

ENV PYTHONUNBUFFERED=1 

EXPOSE 5000

# ▸ comando de entrada – servidor builtin do Flask
CMD ["python", "app.py"]