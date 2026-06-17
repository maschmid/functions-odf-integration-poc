import boto3
import html
import logging
import mimetypes


def new():
    return Function()


class Function:
    def __init__(self):
        self.s3 = None
        self.bucket = None

    def start(self, cfg):
        self.bucket = cfg.get("BUCKET_NAME", "uploads")

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
        path = scope.get("path", "/")

        if method != "GET":
            await self._send_response(send, 405, "Method Not Allowed")
            return

        if path == "/" or path == "":
            await self._handle_list(send)
        else:
            key = path.lstrip("/")
            await self._handle_download(send, key)

    async def _handle_list(self, send):
        try:
            objects = []
            continuation_token = None
            while True:
                kwargs = {"Bucket": self.bucket}
                if continuation_token:
                    kwargs["ContinuationToken"] = continuation_token
                resp = self.s3.list_objects_v2(**kwargs)
                objects.extend(resp.get("Contents", []))
                if not resp.get("IsTruncated"):
                    break
                continuation_token = resp["NextContinuationToken"]
        except Exception:
            logging.exception("Failed to list objects")
            await self._send_response(send, 500, "Failed to list objects")
            return

        rows = ""
        for obj in objects:
            safe_key = html.escape(obj["Key"])
            size = obj.get("Size", 0)
            modified = obj.get("LastModified", "")
            rows += (
                f"<tr>"
                f"<td><a href=\"/{safe_key}\">{safe_key}</a></td>"
                f"<td>{size}</td>"
                f"<td>{modified}</td>"
                f"</tr>\n"
            )

        page = f"""<!DOCTYPE html>
<html>
<head>
  <title>S3 Image Lister</title>
  <style>
    body {{ font-family: sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ text-align: left; padding: 8px 12px; border-bottom: 1px solid #ddd; }}
    th {{ background: #f4f4f4; }}
    a {{ color: #0073bb; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <h1>S3 Image Lister</h1>
  <p>{len(objects)} object(s) in <code>{html.escape(self.bucket)}</code></p>
  <table>
    <thead><tr><th>Key</th><th>Size (bytes)</th><th>Last Modified</th></tr></thead>
    <tbody>
{rows}    </tbody>
  </table>
</body>
</html>
"""
        await self._send_response(send, 200, page, "text/html")

    async def _handle_download(self, send, key):
        try:
            resp = self.s3.get_object(Bucket=self.bucket, Key=key)
        except self.s3.exceptions.NoSuchKey:
            await self._send_response(send, 404, "Not Found")
            return
        except Exception:
            logging.exception("Failed to get object %s", key)
            await self._send_response(send, 500, "Failed to retrieve object")
            return

        content_type = resp.get("ContentType")
        if not content_type:
            content_type = mimetypes.guess_type(key)[0] or "application/octet-stream"

        body = resp["Body"].read()
        await self._send_response(send, 200, body, content_type)

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
