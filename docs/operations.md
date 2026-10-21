# Operations Guide

Practical guide for operating the NSXBet Thumbor service locally and in
staging/production. Fork of [thumbor/thumbor](https://github.com/thumbor/thumbor)
with [thumbor-video-engine](https://github.com/theatlantic/thumbor-video-engine)
for image and video transcoding.

---

## Local Stack

```bash
make run-bg        # thumbor + MinIO + statsd-exporter + prometheus + grafana
make minio-init    # creates the thumbor-media bucket in local MinIO (idempotent)
make test-api      # end-to-end smoke test against the running stack
make stop          # tear down
```

| Service | URL |
|---------|-----|
| Thumbor API | http://localhost:8888 (or `THUMBOR_PORT` if set) |
| MinIO console | http://localhost:9001 (`minioadmin`/`minioadmin`) |
| MinIO S3 API | http://localhost:9000 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (`admin`/`admin`), dashboard auto-provisioned from `monitoring/grafana/` |
| statsd_exporter (metrics) | http://localhost:9102/metrics |

Local S3 is MinIO. Production S3 is real AWS — same code path via
[thumbor-aws](https://github.com/thumbor/thumbor-aws); only endpoint/credentials
change per environment.

## Media Endpoints

### Upload (choose name + prefix)

```
PUT /image/<prefix>/<filename>.<ext>
Header: Content-Type: <mime> (e.g. image/svg+xml, video/webm)
Body:   binary (Postman: Body → binary → select file)
→ 204 No Content (upsert: repeats overwrite silently)
```

Example:

```
PUT /image/sports/team-jerseys/corinthians.svg
→ S3 key: thumbor-media/media/sports/team-jerseys/corinthians.svg
```

Rules:

- `POST /image` always generates a UUID key (no custom name). Use it for
  one-off user content where the id is stored by the caller (from the
  `Location` response header).
- `PUT` accepts arbitrary nested paths. Use it for named assets (banners,
  logos, team kits) where the address is deterministic.
- `GET /image/<path>` returns the original bytes. For `POST`-uploaded
  objects the path is exactly the `Location` value **without** the default
  filename suffix: `GET /image/<uuid>` (no `/image.jpg`).
- Safe characters in paths: `a-z 0-9 - _ . /`. Avoid spaces, `#`, `?`, `%`.
- `DELETE /image/<path>` removes the original (enabled via
  `UPLOAD_DELETE_ALLOWED`). It does **not** invalidate cached transformations
  — see [Invalidation](#invalidation).

### Transformation

```
GET /unsafe/<width>x<height>/<filters>/<source-path>
```

- Dimensions come **before** filters (`/unsafe/300x200/filters:.../src`).
- `0` means proportional (`300x0` = width 300, height auto).
- `fit-in` fits inside the box preserving aspect ratio.

Common filters (chainable, order matters):

| Filter | Example | Effect |
|--------|---------|--------|
| `format()` | `filters:format(png)` | output format: `png`, `jpg`, `webp`, `gif`, `mp4`, `webm` |
| `quality()` | `filters:quality(85)` | JPEG/WebP quality 1–100 |
| `max_age()` | `filters:max_age(3600)` | per-request Cache-Control override |
| `background_color()` | `filters:background_color(FFFFFF)` | fill color for JPG (no alpha) |
| `sharpen()`, `blur()`, `grayscale()` | | pixel effects |

SVG is rasterized on transform (PNG output preserves transparency;
`background_color` needed for JPG).

### Video transcoding

```
PUT /image/videos/aviator/promo.webm           (Content-Type: video/webm)
GET /unsafe/200x150/filters:format(mp4)/videos/aviator/promo.webm
```

- Formats: `mp4` (H.264), `webm` (VP9); animated GIF → WebP animated or MP4.
- Quality is **not** set per-request (security); it is service config:
  - Local: `FFMPEG_H264_CRF=18 FFMPEG_H264_PRESET=slow make run-bg`
  - Staging/prod: env vars in `kubernetes/<env>.yaml`
  - CRF: 18 ≈ visually lossless, 23 default, 28 cheap.
    Preset: `ultrafast … veryslow` (slower = smaller/better, more CPU).
  - Note: CRF is only "lower = better" within the same preset.

## Caching Model

Three independent cache layers. Knowing which is which prevents most
confusion.

### 1. HTTP cache (browser / CDN)

Header `Cache-Control: max-age=N,public` on every response.

| Config | Default | Meaning |
|--------|---------|---------|
| `MAX_AGE` | `86400` (24h) | global TTL advertised to clients |
| `MAX_AGE_TEMP_IMAGE` | `0` | TTL for failed smart-detection responses |
| `filters:max_age(N)` | — | per-request override (wins over global) |

### 2. Result storage (processing cache) — **enabled, 1 year**

Each unique URL (dimensions + filters + source path) produces one immutable
output object. Same URL → same output, forever → cached for 1 year.

```
Config: RESULT_STORAGE            = thumbor_aws.result_storage
        RESULT_STORAGE_EXPIRATION_SECONDS = 31536000  (1 year)
        AWS_RESULT_STORAGE_BUCKET_NAME    = thumbor-media-stg
        AWS_RESULT_STORAGE_ROOT_PATH      = /results
        RESULT_STORAGE_STORES_UNSAFE      = True  (cache /unsafe too)
```

Cache key mirrors the request path 1:1:

```
GET /unsafe/150x150/filters:format(png)/sports/team-jerseys/corinthians.svg
→ stored at: thumbor-media-stg/results/unsafe/150x150/filters:format(png)/sports/team-jerseys/corinthians.svg
```

Verified locally: first request ~100 ms (process + store), repeats ~40 ms
(direct S3 hit, log line `[RESULT_STORAGE] Image retrieved successfully`).

TTL is controlled by `RESULT_STORAGE_EXPIRATION_SECONDS` (checked by
`thumbor_aws` `_is_expired` against the object's `LastModified`).

Overriding per environment: any of these keys is overridable via env vars
(`--use-environment`) in `kubernetes/<env>.yaml`.

### 3. Originals storage

`STORAGE = thumbor_aws.storage` → S3, no TTL. Originals live permanently in
the bucket. Bucket lifecycle rules (platform-iac) are the place to add
expiry if ever needed.

## Invalidation

Overwriting an original (`PUT` same path) does **not** invalidate cached
transformations — cached results keep serving the old output for up to 1
year.

Options:

1. **Preferred: immutable naming.** New content = new path
   (`corinthians-2026.svg`), never overwrite. Cache invalidation problem
   disappears.
2. **Manual:** delete the cached result object(s):

   ```bash
   # list transformations of an asset
   mc ls thumbor-local/thumbor-media --recursive --path "*corinthians*"

   # local
   mc rm thumbor-local/thumbor-media/results/unsafe/150x150/filters:format(png)/sports/team-jerseys/corinthians.svg
   # staging (after ATLANTIS apply provisions the bucket)
   aws s3 rm s3://thumbor-media-stg/results/ --recursive --exclude "*" --include "*corinthians*"
   ```

3. **CDN purge** — when a CDN sits in front, purge the URL there too (HTTP
   cache layer).

## Where Things Live (debugging)

| Question | Where to look |
|----------|---------------|
| Exact S3 key on upload | thumbor logs: `[STORAGE] putting at /media/...` (DEBUG) |
| Cache hit or miss | logs: `[RESULT_STORAGE] getting from` (miss) / `retrieved successfully` (hit) |
| Effective config | `docker compose ... exec thumbor python3 -c "from thumbor.config import Config; c=Config.load('/etc/thumbor/conf/thumbor.local.conf'); print(c.AWS_STORAGE_BUCKET_NAME)"` |
| Objects in bucket | `mc ls thumbor-local/thumbor-media --recursive` or MinIO console |
| Why 404/504 | logs show the exact key attempted (`NoSuchKey Key=...`) |

Log level: local runs `-l debug`; staging/prod `-l info` (upgrade
`RESULT_STORAGE` lines to INFO already visible).

## Deployment (staging)

1. Merge [NSXBet/thumbor#1](https://github.com/NSXBet/thumbor/pull/1)
   (service code, Dockerfile, manifests).
2. Apply [NSXBet/platform-iac#477](https://github.com/NSXBet/platform-iac/pull/477)
   via Atlantis (`atlantis apply`) — creates bucket `thumbor-media-stg` +
   IRSA role `Thumbor-Staging-EKSServiceAccountRole` (no secrets; pod
   assumes the role via OIDC).
3. Merge [NSXBet/monorepo-gitops#589](https://github.com/NSXBet/monorepo-gitops/pull/589)
   — ArgoCD picks `apps-config/thumbor/staging`.
4. Trigger deploy: Actions → *GitHub Builder Remote Workflow*
   (`remote_workflow.yaml`) → environment `staging`.

ARN in `kubernetes/staging.yaml` must match the role created by platform-iac.

## Pending Work

- Security key + signed URLs (drop `/unsafe` in staging/prod).
- Upload auth/rate-limit (any in-cluster caller can PUT today).
- Import `monitoring/grafana/thumbor_overview.json` into hosted Grafana
  (API key lacks `dashboards:create`).
- Alerts (5xx rate, p95 latency) on the imported dashboard.
- Result-storage cache metrics/GC review after real traffic.
