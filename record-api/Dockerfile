########################################
#  Record-API – Dockerfile (DEV)
########################################
FROM python:3.12-slim

WORKDIR /app

# ── dependências de sistema p/ psycopg2
RUN apt-get update && \
    apt-get install -y gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# ── 1ª camada: requirements.txt (agora no diretório raiz do contexto)
COPY requirements.txt ./requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ── 2ª camada: apenas o código-fonte dentro de src/
COPY src/ .

ENV PYTHONUNBUFFERED=1
EXPOSE 5000

CMD ["python", "app.py"]