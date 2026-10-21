# NSXBet: statsd-over-TCP metrics backend.
# Same interface as thumbor.metrics.statsd_metrics but uses TCPStatsClient —
# UDP packets between containers are unreliable on Docker Desktop (macOS).
# All sends are best-effort: a missing statsd endpoint must never break
# image serving (thumbor.metrics.statsd_metrics is fire-and-forget over UDP;
# TCP connect raises, so we swallow send errors).
from statsd import TCPStatsClient

from thumbor.metrics import BaseMetrics


class Metrics(BaseMetrics):
    @classmethod
    def client(cls, config):
        if not hasattr(cls, "_client"):
            cls._client = TCPStatsClient(
                config.STATSD_HOST, config.STATSD_PORT, config.STATSD_PREFIX
            )
        return cls._client

    def incr(self, metricname, value=1):
        try:
            Metrics.client(self.config).incr(metricname, value)
        except OSError:
            pass

    def timing(self, metricname, value):
        try:
            Metrics.client(self.config).timing(metricname, value)
        except OSError:
            pass
