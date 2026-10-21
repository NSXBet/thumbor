# NSXBet upload handler list — additive workaround.
#
# thumbor-video-engine's Engine.load() reads self.context.request (via
# get_engine → accepts_video), which is NOT set by the upload handlers
# (core bug: ImageApiHandler.validate runs before RequestParameters exist).
# We patch ImageApiHandler.validate to provision a minimal request shim
# before delegating to the upstream implementation, so /image POST/PUT work
# with the video engine enabled.
from typing import Any

from thumbor.handlers import ContextHandler, ImageApiHandler
from thumbor.handlers.image_resource import ImageResourceHandler
from thumbor.handlers.upload import ImageUploadHandler
from thumbor.handler_lists import HandlerList


def _patch_validate() -> None:
    original = ImageApiHandler.validate

    def validate(self, body):  # pylint: disable=invalid-name
        if not hasattr(self.context, "request"):
            class _ShimRequest:  # pylint: disable=too-few-public-methods
                accepts_video = False
                accepts_webp = False
                format = None
                filters = ""

            self.context.request = _ShimRequest()
        return original(self, body)

    ImageApiHandler.validate = validate  # type: ignore[method-assign]


_patch_validate()


def get_handlers(context: Any) -> HandlerList:
    if not context.config.UPLOAD_ENABLED:
        return []

    return [
        (r"/image", ImageUploadHandler, {"context": context}),
        (r"/image/(.*)", ImageResourceHandler, {"context": context}),
    ]
