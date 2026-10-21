#!/usr/bin/env bash
# NSXBet Thumbor API smoke test.
# Requires: make run-bg && make minio-init (stack up). Exits non-zero on first failure.
set -euo pipefail

BASE="${THUMBOR_BASE:-http://localhost:8888}"
METRICS="${STATSD_EXPORTER_BASE:-http://localhost:9102}"
FIXTURES="$(cd "$(dirname "$0")/../docker/fixtures" && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== 1. healthcheck"
curl -fsS "$BASE/healthcheck" | grep -q "WORKING" || fail "healthcheck did not return WORKING"
echo "ok"

echo "== 2. upload JPEG to S3 (POST /image)"
UP_HDR=$(curl -s -X POST "$BASE/image" -H "Content-Type: image/jpeg" --data-binary @"$FIXTURES/test.jpg" -D- -o /dev/null)
echo "$UP_HDR" | grep -q "201 Created" || fail "expected 201 on upload"
JPG_ID=$(echo "$UP_HDR" | sed -n 's|.*Location: /image/\([a-f0-9]*\).*|\1|p' | head -1 || true)
[[ -n "$JPG_ID" ]] || fail "no Location header with file id on upload"
echo "id: $JPG_ID"

echo "== 3. upload animated GIF to S3 (POST /image)"
UP_HDR=$(curl -s -X POST "$BASE/image" -H "Content-Type: image/gif" --data-binary @"$FIXTURES/test.gif" -D- -o /dev/null)
echo "$UP_HDR" | grep -q "201 Created" || fail "expected 201 on gif upload"
GIF_ID=$(echo "$UP_HDR" | sed -n 's|.*Location: /image/\([a-f0-9]*\).*|\1|p' | head -1 || true)
[[ -n "$GIF_ID" ]] || fail "no Location header with file id on gif upload"
echo "id: $GIF_ID"

echo "== 4. raw media GET (GET /image/<id>)"
CT=$(curl -fsS -o /dev/null -w '%{content_type}' "$BASE/image/$GIF_ID")
[[ "$CT" == "image/gif" ]] || fail "expected image/gif on media GET, got $CT"

echo "== 5. image happy path (resize uploaded JPEG)"
CT=$(curl -fsS -o /dev/null -w '%{content_type}' "$BASE/unsafe/300x200/$JPG_ID")
echo "content-type: $CT"
[[ "$CT" == image/* ]] || fail "expected image/* content-type, got $CT"

echo "== 6. GIF -> animated WebP (filters:format(webp))"
CT=$(curl -fsS -H "Accept: image/webp" -o /dev/null -w '%{content_type}' "$BASE/unsafe/100x100/filters:format(webp)/$GIF_ID")
echo "content-type: $CT"
[[ "$CT" == "image/webp" ]] || fail "expected image/webp, got $CT"

echo "== 7. GIF -> H264 MP4 (Accept: video/*)"
CT=$(curl -fsS -H "Accept: video/*" -o /dev/null -w '%{content_type}' "$BASE/unsafe/100x100/$GIF_ID")
echo "content-type: $CT"
[[ "$CT" == "video/mp4" ]] || fail "expected video/mp4, got $CT"

echo "== 8. missing source -> error (4xx or 504: http_loader DNS failure)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/unsafe/100x100/not-there")
echo "status: $CODE"
[[ "$CODE" =~ ^4|^5 ]] || fail "expected error status for missing source, got $CODE"

echo "== 9. statsd metrics exposed via statsd_exporter"
curl -fsS "$METRICS/metrics" | grep -q "^statsd_" || fail "no statsd_ series in exporter metrics"
curl -fsS "$METRICS/metrics" | grep -q "thumbor" || fail "no thumbor statsd series found"
echo "ok"

echo "ALL PASSED"
