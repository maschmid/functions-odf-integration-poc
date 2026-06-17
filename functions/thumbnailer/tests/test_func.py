import json
import os
import pytest
from unittest.mock import MagicMock, patch, ANY
from PIL import Image

from function import new


NOTIFICATION = {
    "Records": [{
        "eventVersion": "2.3",
        "eventSource": "noobaa:s3",
        "s3": {
            "object": {
                "key": "uploads/2026/06/17/abc-photo.jpg",
                "size": 1024,
            },
            "bucket": {
                "name": "foo-bucket",
            },
        },
        "eventName": "ObjectCreated:Put",
    }]
}


def _make_receive(body: bytes):
    async def receive():
        return {"body": body, "more_body": False}
    return receive


def _make_send():
    messages = []

    async def send(message):
        messages.append(message)

    send.messages = messages
    return send


def _create_test_image(path):
    img = Image.new("RGB", (200, 100), color="red")
    img.save(path)


class TestThumbnailer:
    @pytest.mark.asyncio
    async def test_rejects_get(self):
        f = new()
        send = _make_send()
        await f.handle({"method": "GET"}, _make_receive(b""), send)
        assert send.messages[0]["status"] == 405

    @pytest.mark.asyncio
    async def test_rejects_invalid_json(self):
        f = new()
        f.start({})
        send = _make_send()
        await f.handle(
            {"method": "POST"}, _make_receive(b"not json"), send,
        )
        assert send.messages[0]["status"] == 400

    @pytest.mark.asyncio
    async def test_rejects_empty_records(self):
        f = new()
        f.start({})
        send = _make_send()
        await f.handle(
            {"method": "POST"},
            _make_receive(json.dumps({"Records": []}).encode()),
            send,
        )
        assert send.messages[0]["status"] == 400

    @pytest.mark.asyncio
    async def test_thumbnail_success(self, tmp_path):
        f = new()

        mock_input_s3 = MagicMock()
        mock_output_s3 = MagicMock()
        f.input_s3 = mock_input_s3
        f.output_s3 = mock_output_s3
        f.output_bucket = "thumbnails"

        def fake_download(bucket, key, path):
            _create_test_image(path)

        mock_input_s3.download_file.side_effect = fake_download

        send = _make_send()
        await f.handle(
            {"method": "POST"},
            _make_receive(json.dumps(NOTIFICATION).encode()),
            send,
        )

        assert send.messages[0]["status"] == 200
        mock_input_s3.download_file.assert_called_once_with(
            "foo-bucket", "uploads/2026/06/17/abc-photo.jpg", ANY,
        )
        mock_output_s3.upload_file.assert_called_once_with(
            ANY, "thumbnails", "resized/uploads/2026/06/17/abc-photo.jpg",
        )

        body = json.loads(send.messages[1]["body"])
        assert len(body["thumbnailed"]) == 1
        assert body["thumbnailed"][0]["source"] == "uploads/2026/06/17/abc-photo.jpg"

    @pytest.mark.asyncio
    async def test_start_configures_two_s3_clients(self):
        f = new()
        with patch("function.func.boto3.client") as mock_client:
            f.start({
                "INPUT_BUCKET_HOST": "input.noobaa.svc",
                "INPUT_BUCKET_PORT": "443",
                "INPUT_BUCKET_ACCESS_KEY_ID": "in-key",
                "INPUT_BUCKET_SECRET_ACCESS_KEY": "in-secret",
                "OUTPUT_BUCKET_HOST": "output.noobaa.svc",
                "OUTPUT_BUCKET_PORT": "443",
                "OUTPUT_BUCKET_NAME": "my-thumbs",
                "OUTPUT_BUCKET_ACCESS_KEY_ID": "out-key",
                "OUTPUT_BUCKET_SECRET_ACCESS_KEY": "out-secret",
            })

        assert mock_client.call_count == 2
        calls = mock_client.call_args_list

        assert calls[0].kwargs["endpoint_url"] == "https://input.noobaa.svc:443"
        assert calls[0].kwargs["aws_access_key_id"] == "in-key"

        assert calls[1].kwargs["endpoint_url"] == "https://output.noobaa.svc:443"
        assert calls[1].kwargs["aws_access_key_id"] == "out-key"

        assert f.output_bucket == "my-thumbs"
