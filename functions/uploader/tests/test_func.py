import pytest
from unittest.mock import MagicMock, patch
from function import new


@pytest.mark.asyncio
async def test_get_returns_upload_form():
    f = new()
    scope = {"method": "GET", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 200
    assert [b"content-type", b"text/html"] in responses[0]["headers"]
    assert b"Upload" in responses[1]["body"]
    assert b'enctype="multipart/form-data"' in responses[1]["body"]


@pytest.mark.asyncio
async def test_post_uploads_to_s3():
    f = new()

    mock_s3 = MagicMock()
    f.s3 = mock_s3
    f.bucket = "test-bucket"

    boundary = "----TestBoundary"
    body = (
        f"------TestBoundary\r\n"
        f'Content-Disposition: form-data; name="file"; filename="test.png"\r\n'
        f"Content-Type: image/png\r\n"
        f"\r\n"
        f"fakepngdata\r\n"
        f"------TestBoundary--\r\n"
    ).encode()

    scope = {
        "method": "POST",
        "headers": [
            [b"content-type", f"multipart/form-data; boundary=----TestBoundary".encode()],
        ],
    }

    received = False

    async def receive():
        nonlocal received
        if not received:
            received = True
            return {"type": "http.request", "body": body, "more_body": False}
        return {"type": "http.request", "body": b"", "more_body": False}

    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, receive, send)

    assert responses[0]["status"] == 200
    mock_s3.put_object.assert_called_once()
    call_kwargs = mock_s3.put_object.call_args[1]
    assert call_kwargs["Bucket"] == "test-bucket"
    assert "test.png" in call_kwargs["Key"]
    assert call_kwargs["Body"] == b"fakepngdata"


@pytest.mark.asyncio
async def test_post_no_file_returns_400():
    f = new()
    f.s3 = MagicMock()
    f.bucket = "test-bucket"

    scope = {
        "method": "POST",
        "headers": [
            [b"content-type", b"multipart/form-data; boundary=----TestBoundary"],
        ],
    }

    async def receive():
        return {"type": "http.request", "body": b"------TestBoundary--\r\n", "more_body": False}

    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, receive, send)

    assert responses[0]["status"] == 400
