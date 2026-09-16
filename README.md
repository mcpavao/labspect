# labspect.com

My portfolio site, served from a single-node k3s cluster running on an HP t620
thin client in my flat in Lyon. No ports are open on the router: the cluster
pulls its image from a registry and reaches the outside world through an
outbound tunnel.

Live at **[labspect.com](https://labspect.com)**.

---

## Why this exists

Building the site was the easy part. The point was to own the whole chain —
the operating system, the cluster, the delivery pipeline and the cost — on
hardware I already had, and to keep it running.

Running total: about **€3.50 a month** (electricity plus the domain).
The server itself was a 2013 thin client sitting unused in a drawer.

---

## Architecture

```
git push
   │
   ▼
GitHub Actions ──► GHCR (container registry)
                        │
                        │ the cluster pulls
                        ▼
        ┌───────────────────────────────────┐
        │  k3s · HP t620 · at home          │
        │                                   │
        │   cloudflared  ───►  nginx        │
        │        │                          │
        └────────┼──────────────────────────┘
                 │ outbound tunnel only
                 ▼
            Cloudflare  ◄───  visitor
```

The direction of that last arrow is the whole design. The cluster never
accepts an inbound connection. `cloudflared` dials out to Cloudflare and keeps
the connection open; traffic for `labspect.com` comes back down that tunnel.

Consequences:

- no port forwarding on the ISP router
- the residential IP address is never exposed
- TLS, caching and DDoS protection are handled at the edge
- it works behind CGNAT

---

## Hardware

| | |
|---|---|
| Machine | HP t620 thin client (2013) |
| CPU | AMD GX-217GA, 2 cores, 1.65 GHz, 15 W TDP |
| RAM | 8 GB DDR3L |
| Storage | SanDisk U110 M.2 SATA, 16 GB |
| OS | Debian 13, headless |
| Network | Gigabit ethernet, DHCP reservation on the router |

Sixteen gigabytes of storage is tight, so the system is tuned for a flash
device that was designed to be written to rarely: `noatime` on the root
filesystem and `journald` capped at 200 MB.

---

## Repository layout

```
.
├── site/
│   └── index.html                     the site itself, self-contained
├── nginx.conf                         server config baked into the image
├── Dockerfile                         how the image is built
├── .github/
│   └── workflows/
│       └── build.yml                  CI: build and publish on push
└── clusters/
    └── homelab/
        ├── web/
        │   └── nginx.yaml             Deployment + Service for the site
        └── tools/
            └── cloudflared.yaml       the tunnel connector
```

### `site/index.html`

One self-contained file: markup, styles and a small script for the FR/EN
toggle. No build step, no framework, no dependency beyond two web fonts.
The diagrams and charts are hand-written SVG rather than images, so they stay
sharp, respect `prefers-reduced-motion` and weigh nothing.

### `nginx.conf`

Replaces the default config inside the image. Enables gzip, sets cache
headers (long for assets, `no-cache` for HTML so a deploy is visible
immediately) and adds the usual security headers. TLS is not handled here —
Cloudflare terminates it at the edge.

### `Dockerfile`

Three meaningful lines: start from `nginx:alpine`, copy the site in, copy the
config in. The resulting image is around 60 MB and starts in under a second,
which matters on a CPU this slow.

### `.github/workflows/build.yml`

On a pull request it validates the HTML and builds the image without
publishing — a broken Dockerfile is caught before merge. On a push to `main`
it builds and pushes to GHCR, tagged both `latest` and with the commit SHA,
so any deploy can be traced back to a specific commit.

Authentication uses the repository's own `GITHUB_TOKEN`. No long-lived
credential is stored anywhere.

### `clusters/homelab/web/nginx.yaml`

The Deployment and Service for the site. Rolling update with
`maxUnavailable: 0`, so the old pod keeps serving until the new one passes its
readiness probe. Memory is capped — on an 8 GB machine, an unbounded pod is a
machine you lose.

### `clusters/homelab/tools/cloudflared.yaml`

The tunnel connector, running as an ordinary workload rather than installed on
the host. The tunnel token comes from a Kubernetes Secret created out of band;
it is deliberately **not** in this repository.

---

## Reproducing it

Assuming Debian and a Cloudflare account with a domain:

```bash
# cluster
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# namespaces
kubectl create namespace web
kubectl create namespace tools

# tunnel credentials, created from the Cloudflare dashboard token
kubectl create secret generic cloudflared-token -n tools \
  --from-literal=token='<token>'

# workloads
kubectl apply -f clusters/homelab/tools/cloudflared.yaml
kubectl apply -f clusters/homelab/web/nginx.yaml
```

The Cloudflare tunnel needs one public hostname pointing at
`nginx.web.svc.cluster.local:80`.

---

## Known gaps

Worth stating plainly, because a homelab that claims to be finished usually
isn't.

- **Deployment is still manual.** CI publishes the image; applying it is a
  `kubectl rollout restart`. Automating it properly means GitOps — a
  controller inside the cluster watching this repository — rather than giving
  a CI runner credentials to the cluster API. That is the next piece.
- **No monitoring yet.** No metrics, no alerting. If the site goes down at
  3 a.m. I find out when I look.
- **Single node, single disk.** No redundancy. The manifests are in Git and
  the data is backed up, so recovery means reinstalling — which is the point
  of keeping everything declarative, but it is recovery, not availability.
- **Electricity cost is estimated**, not measured at the socket.

---

## Notes

The README is in English because that is the convention for public
repositories. The site itself is bilingual French and English.


## Decision about Prometheus and Grafana
O Grafana é publicado via túnel Cloudflare com Cloudflare Access na frente, em modelo default-deny com whitelist por e-mail. O painel nunca fica acessível na internet aberta, e o cluster não expõe nenhuma porta. O acesso passa pelo Traefik, mantendo um ponto único de entrada para roteamento e observabilidade.

## Test False Positive with BetterStack 
O monitoramento interno roda no mesmo cluster que observa, então não detecta a queda do próprio host. Um verificador externo cobre esse ponto cego: se o servidor ficar indisponível, o alerta parte de fora da infraestrutura observada.