import boto3
import html
import logging
import mimetypes
import uuid
from datetime import datetime, timezone


UPLOAD_FORM = """<!DOCTYPE html>
<html>
<head>
  <title>S3 Image Uploader</title>
  <style>
    body { font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; }
    .drop-zone { border: 2px dashed #ccc; border-radius: 8px; padding: 40px; text-align: center; }
    .drop-zone:hover { border-color: #666; }
    button { background: #0073bb; color: white; border: none; padding: 10px 24px;
             border-radius: 4px; cursor: pointer; font-size: 16px; margin-top: 16px; }
    button:hover { background: #005a92; }
  </style>
</head>
<body>
  <h1>S3 Image Uploader</h1>
  <form method="POST" enctype="multipart/form-data">
    <div class="drop-zone">
      <p>Select an image to upload to S3</p>
      <input type="file" name="file" accept="image/*" required>
    </div>
    <button type="submit">Upload to S3</button>
  </form>
</body>
</html>
"""


def new():
    return Function()


class Function:
    def __init__(self):
        self.s3 = None
        self.bucket = None

    def start(self, cfg):
        self.bucket = cfg.get("BUCKET_NAME", "uploads")

        # boto3 picks up AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from the
        # environment automatically — same as in AWS Lambda.
        # Build the endpoint URL from noobaa's BUCKET_HOST and BUCKET_PORT.
        host = cfg.get("BUCKET_HOST", "")
        port = cfg.get("BUCKET_PORT", "443")
        endpoint_url = f"https://{host}:{port}" if host else None
        self.s3 = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            verify=False,
        )
        logging.info("S3 client configured (bucket=%s, endpoint=%s)",
                     self.bucket, endpoint_url)

    async def handle(self, scope, receive, send):
        method = scope.get("method", "GET")

        if method == "GET":
            await self._send_response(send, 200, UPLOAD_FORM, "text/html")
            return

        if method == "POST":
            await self._handle_upload(scope, receive, send)
            return

        await self._send_response(send, 405, "Method Not Allowed")

    async def _handle_upload(self, scope, receive, send):
        content_type = self._get_header(scope, "content-type")
        body = await self._read_body(receive)

        filename, file_data = self._parse_multipart(body, content_type)
        if not filename or not file_data:
            await self._send_response(send, 400, "No file uploaded")
            return

        # Generate a unique S3 key — same pattern as typical Lambda/S3 examples
        key = (
            f"uploads/"
            f"{datetime.now(timezone.utc).strftime('%Y/%m/%d')}/"
            f"{uuid.uuid4()}-{filename}"
        )

        # Upload to S3 — the same put_object() call you would use in Lambda
        content_type_header = (
            mimetypes.guess_type(filename)[0] or "application/octet-stream"
        )
        self.s3.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=file_data,
            ContentType=content_type_header,
        )

        logging.info("Uploaded %s to s3://%s/%s (%d bytes)",
                     filename, self.bucket, key, len(file_data))

        safe_name = html.escape(filename)
        safe_key = html.escape(key)
        success_html = f"""<!DOCTYPE html>
<html>
<head><title>Upload Successful</title>
<style>
  body {{ font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; }}
  code {{ background: #f4f4f4; padding: 4px 8px; border-radius: 4px; }}
  a {{ color: #0073bb; }}
</style>
</head>
<body>
  <h1>Upload Successful</h1>
  <p>File <strong>{safe_name}</strong> uploaded to:</p>
  <p><code>s3://{html.escape(self.bucket)}/{safe_key}</code></p>
  <a href="/">Upload another file</a>
</body>
</html>
"""
        await self._send_response(send, 200, success_html, "text/html")

    # -- helpers (ASGI plumbing) -------------------------------------------

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
    def _get_header(scope, name):
        for key, value in scope.get("headers", []):
            if key.lower() == name.encode() if isinstance(key, str) else key == name.encode():
                return value.decode() if isinstance(value, bytes) else value
        return ""

    @staticmethod
    def _parse_multipart(body, content_type):
        """Extract the first uploaded file from a multipart/form-data body."""
        if not content_type or "multipart/form-data" not in content_type:
            return None, None

        boundary = None
        for part in content_type.split(";"):
            part = part.strip()
            if part.startswith("boundary="):
                boundary = part[len("boundary="):].strip('"')
                break
        if not boundary:
            return None, None

        delimiter = ("--" + boundary).encode()
        parts = body.split(delimiter)

        for part in parts:
            if b"Content-Disposition" not in part:
                continue

            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue

            headers_raw = part[:header_end].decode("utf-8", errors="replace")
            file_data = part[header_end + 4:]

            if file_data.endswith(b"\r\n"):
                file_data = file_data[:-2]

            if 'filename="' in headers_raw:
                filename = headers_raw.split('filename="')[1].split('"')[0]
                if filename:
                    return filename, file_data

        return None, None

    @staticmethod
    async def _send_response(send, status, body, content_type="text/plain"):
        body_bytes = body.encode() if isinstance(body, str) else body
        await send({
            "type": "http.response.start",
            "status": status,
            "headers": [
                [b"content-type", content_type.encode()],
            ],
        })
        await send({
            "type": "http.response.body",
            "body": body_bytes,
        })

    def stop(self):
        logging.info("Function stopping")

    def alive(self):
        return True, "Alive"

    def ready(self):
        return True, "Ready"
