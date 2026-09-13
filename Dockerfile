FROM nginx:1.29-alpine

# Le site est statique : on copie les fichiers dans la racine servie par nginx.
COPY site/ /usr/share/nginx/html/

# Configuration minimale : compression, cache, en-têtes de sécurité.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# nginx:alpine tourne déjà en non-root pour les workers.
EXPOSE 80

# Sonde utilisée par le readinessProbe de Kubernetes.
HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://127.0.0.1/ || exit 1
