import boto3
import json
import logging
import tempfile
import uuid
from urllib.parse import unquote_plus

from PIL import Image


def new():
    return Function()


class Function:
    def __init__(self):
        self.input_s3 = None
        self.output_s3 = None
        self.output_bucket = None

    def start(self, cfg):
        self.input_s3 = self._make_s3_client(cfg, "INPUT_BUCKET")
        self.output_s3 = self._make_s3_client(cfg, "OUTPUT_BUCKET")
        self.output_bucket = cfg.get("OUTPUT_BUCKET_NAME", "thumbnails")
        logging.info("Thumbnailer ready (output_bucket=%s)", self.output_bucket)

    async def handle(self, scope, receive, send):
        method = scope.get("method", "GET")

        if method != "POST":
            await self._send_response(send, 405, "Method Not Allowed")
            return

        body = await self._read_body(receive)
        try:
            event = json.loads(body)
        except (json.JSONDecodeError, TypeError):
            await self._send_response(send, 400, "Invalid JSON")
            return

        records = event.get("Records", [])
        if not records:
            await self._send_response(send, 400, "No records in event")
            return

        results = []
        for record in records:
            bucket = record["s3"]["bucket"]["name"]
            key = unquote_plus(record["s3"]["object"]["key"])

            with tempfile.TemporaryDirectory() as tmpdir:
                safe_name = key.replace("/", "_")
                download_path = f"{tmpdir}/{uuid.uuid4()}-{safe_name}"
                resized_path = f"{tmpdir}/resized-{safe_name}"

                self.input_s3.download_file(bucket, key, download_path)

                with Image.open(download_path) as image:
                    image.thumbnail(tuple(x // 2 for x in image.size))
                    image.save(resized_path)

                output_key = f"resized/{key}"
                self.output_s3.upload_file(
                    resized_path, self.output_bucket, output_key,
                )

            logging.info("Thumbnailed s3://%s/%s -> s3://%s/%s",
                         bucket, key, self.output_bucket, output_key)
            results.append({"source": key, "destination": output_key})

        await self._send_response(
            send, 200, json.dumps({"thumbnailed": results}), "application/json",
        )

    @staticmethod
    def _make_s3_client(cfg, prefix):
        host = cfg.get(f"{prefix}_HOST", "")
        port = cfg.get(f"{prefix}_PORT", "443")
        endpoint_url = f"https://{host}:{port}" if host else None
        return boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=cfg.get(f"{prefix}_ACCESS_KEY_ID"),
            aws_secret_access_key=cfg.get(f"{prefix}_SECRET_ACCESS_KEY"),
            verify=False,
        )

    @staticmethod
    async def _read_body(receive):
        body = b""
        while True:
            message = await receive()
            body += message.get("body", b"")
            if not message.get("more_body", False):
                break
        return body

    @staticmethod
    async def _send_response(send, status, body, content_type="text/plain"):
        body_bytes = body.encode() if isinstance(body, str) else body
        await send({
            "type": "http.response.start",
            "status": status,
            "headers": [[b"content-type", content_type.encode()]],
        })
        await send({"type": "http.response.body", "body": body_bytes})

    def stop(self):
        logging.info("Function stopping")

    def alive(self):
        return True, "Alive"

    def ready(self):
        return True, "Ready"
