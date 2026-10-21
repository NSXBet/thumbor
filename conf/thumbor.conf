# NSXBet Thumbor — Thumbor imaging service with video transcoding
# Fork of https://github.com/thumbor/thumbor
#
# Usage: thumbor -c /etc/thumbor/thumbor.conf -p 8888

# --- Security ---
# SECURITY_KEY can be overridden via env (--use-environment) or secret manager.
# 'unsafe' URLs are allowed only for local testing (thumbor.local.conf overrides).
ALLOW_UNSAFE_URL = False
# --- Upload API ---
# POST /image and PUT|GET|DELETE /image/<file_id> (handler_lists.upload).
# UPLOAD_PHOTO_STORAGE points at S3 (thumbor-aws) — see AWS section below.
UPLOAD_ENABLED = True
UPLOAD_PUT_ALLOWED = True
UPLOAD_DELETE_ALLOWED = True
UPLOAD_MAX_SIZE = 0  # no upload size limit (set bytes to cap)
MIN_WIDTH = 1
MIN_HEIGHT = 1
# Custom upload handler list: patches video-engine + upload interaction.
HANDLER_LISTS = ['thumbor.handler_lists.healthcheck', 'thumbor.handler_lists.blacklist', 'nsx.upload_compat']
# --- Sources (regexes match hostname; video-engine loader uses http_loader) ---
ALLOWED_SOURCES = [
    r'.*\.nsx\.services',
    r'.*\.nsxbet\.com\.br',
    r'.*\.betnacional\.bet\.br',
]

# --- Loader / Storage ---
LOADER = 'thumbor.loaders.http_loader'
STORAGE = 'thumbor.storages.no_storage'
RESULT_STORAGE = 'thumbor.result_storages.no_storage'

# --- Engine ---
ENGINE = 'thumbor_video_engine.engines.video'
# Non-video files fall back to PIL inside the video engine (IMAGING_ENGINE).
ENGINE_THREADPOOL_SIZE = 4

MAX_PIXELS = 8294400  # 4K: 3840x2160 — guard against decompression bombs

# --- Video engine (thumbor-video-engine) ---
AUTO_WEBP = True  # required for FFMPEG_GIF_AUTO_WEBP (Accept header path)
FFMPEG_GIF_AUTO_WEBP = True
FFMPEG_PATH = '/usr/bin/ffmpeg'
FFPROBE_PATH = '/usr/bin/ffprobe'
FFMPEG_GIF_AUTO_H264 = True
FFMPEG_H264_PRESET = 'medium'   # ultrafast..veryslow: slower = smaller/better, mais CPU
FFMPEG_H264_CRF = 23            # quality: 0=sem perda, 18≈visualmente lossless, 23 default, 28=mais comprimido
MAX_ANIMATED_GIF_PIXELS = 0

# --- Filters ---
# Video-engine format filter REPLACES builtin thumbor.filters.format
# (must not be listed twice). Rest are the builtin filters.
FILTERS = [
    'thumbor_video_engine.filters.format',
    'thumbor.filters.brightness',
    'thumbor.filters.colorize',
    'thumbor.filters.contrast',
    'thumbor.filters.rgb',
    'thumbor.filters.round_corner',
    'thumbor.filters.quality',
    'thumbor.filters.noise',
    'thumbor.filters.watermark',
    'thumbor.filters.equalize',
    'thumbor.filters.fill',
    'thumbor.filters.sharpen',
    'thumbor.filters.strip_exif',
    'thumbor.filters.strip_icc',
    'thumbor.filters.frame',
    'thumbor.filters.grayscale',
    'thumbor.filters.rotate',
    'thumbor.filters.max_bytes',
    'thumbor.filters.convolution',
    'thumbor.filters.blur',
    'thumbor.filters.extract_focal',
    'thumbor.filters.focal',
    'thumbor.filters.no_upscale',
    'thumbor.filters.saturation',
    'thumbor.filters.max_age',
    'thumbor.filters.curve',
    'thumbor.filters.background_color',
    'thumbor.filters.upscale',
    'thumbor.filters.proportion',
    'thumbor.filters.stretch',
]

# --- Metrics ---
# statsd -> statsd_exporter -> Prometheus (see docker/docker-compose.nsx.yaml)
METRICS = 'nsx.metrics'
STATSD_HOST = 'statsd-exporter'
STATSD_PORT = 9125  # statsd_exporter TCP listener (UDP lossy in Docker Desktop)
STATSD_PREFIX = 'thumbor'

# --- S3 storage (thumbor-aws) ---
# Uploads go to S3 via /image; loader reads originals from the same bucket.
# Values overridable via env (--use-environment) for bucket/keys per env.
STORAGE = 'thumbor_aws.storage'
UPLOAD_PHOTO_STORAGE = 'thumbor_aws.storage'
RESULT_STORAGE = 'thumbor.result_storages.no_storage'

AWS_DEFAULT_LOCATION = 'https://{bucket_name}.s3.amazonaws.com'
AWS_STORAGE_REGION_NAME = 'us-east-1'
AWS_STORAGE_BUCKET_NAME = 'thumbor-media-stg'
AWS_STORAGE_ROOT_PATH = '/media'
AWS_LOADER_REGION_NAME = 'us-east-1'
AWS_LOADER_BUCKET_NAME = 'thumbor-media-stg'
AWS_LOADER_ROOT_PATH = '/media'

# Local stack overrides these via conf/thumbor.local.conf to point at MinIO.
AWS_STORAGE_S3_ENDPOINT_URL = None
AWS_LOADER_S3_ENDPOINT_URL = None
