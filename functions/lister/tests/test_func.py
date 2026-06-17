import pytest
from unittest.mock import MagicMock
from function import new


@pytest.mark.asyncio
async def test_get_root_lists_objects():
    f = new()
    f.s3 = MagicMock()
    f.bucket = "test-bucket"
    f.s3.list_objects_v2.return_value = {
        "Contents": [
            {"Key": "uploads/img.png", "Size": 1234, "LastModified": "2026-01-01"},
            {"Key": "uploads/photo.jpg", "Size": 5678, "LastModified": "2026-01-02"},
        ],
        "IsTruncated": False,
    }

    scope = {"method": "GET", "path": "/", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 200
    assert [b"content-type", b"text/html"] in responses[0]["headers"]
    body = responses[1]["body"]
    assert b"uploads/img.png" in body
    assert b"uploads/photo.jpg" in body
    assert b"2 object(s)" in body
    f.s3.list_objects_v2.assert_called_once_with(Bucket="test-bucket")


@pytest.mark.asyncio
async def test_get_root_empty_bucket():
    f = new()
    f.s3 = MagicMock()
    f.bucket = "test-bucket"
    f.s3.list_objects_v2.return_value = {"IsTruncated": False}

    scope = {"method": "GET", "path": "/", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 200
    assert b"0 object(s)" in responses[1]["body"]


@pytest.mark.asyncio
async def test_get_file_returns_content():
    f = new()
    f.s3 = MagicMock()
    f.bucket = "test-bucket"

    mock_body = MagicMock()
    mock_body.read.return_value = b"fake-png-data"
    f.s3.get_object.return_value = {
        "ContentType": "image/png",
        "Body": mock_body,
    }

    scope = {"method": "GET", "path": "/uploads/img.png", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 200
    assert [b"content-type", b"image/png"] in responses[0]["headers"]
    assert responses[1]["body"] == b"fake-png-data"
    f.s3.get_object.assert_called_once_with(Bucket="test-bucket", Key="uploads/img.png")


@pytest.mark.asyncio
async def test_get_file_not_found():
    f = new()
    f.s3 = MagicMock()
    f.bucket = "test-bucket"

    error = type("NoSuchKey", (Exception,), {})
    f.s3.exceptions.NoSuchKey = error
    f.s3.get_object.side_effect = error("Not found")

    scope = {"method": "GET", "path": "/no-such-file.txt", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 404


@pytest.mark.asyncio
async def test_post_returns_405():
    f = new()

    scope = {"method": "POST", "path": "/", "headers": []}
    responses = []

    async def send(message):
        responses.append(message)

    await f.handle(scope, None, send)

    assert responses[0]["status"] == 405
