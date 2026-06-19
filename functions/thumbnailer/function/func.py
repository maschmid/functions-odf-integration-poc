import logging
import boto3
import os
import sys
import uuid
from urllib.parse import unquote_plus
from PIL import Image
import PIL.Image

def resize_image(image_path, resized_path):
    with Image.open(image_path) as image:
        image.thumbnail(tuple(x / 2 for x in image.size))
        image.save(resized_path)

def new():
    return Function()

class Function:
    def start(self, cfg):
        self.s3_client = boto3.client(
            "s3",
            endpoint_url="https://{}:{}".format(cfg.get("S3_HOST"), cfg.get("S3_PORT", 443)),
            aws_access_key_id=cfg.get("AWS_ACCESS_KEY_ID"),
            aws_secret_access_key=cfg.get("AWS_SECRET_ACCESS_KEY"),
            verify=False,
        )
 
    async def handle(self, scope, receive, send):
        event = scope["event"]
        event_data = event.get_data()

        logging.info("Event data: " + repr(event_data))

        for record in event_data['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])

            logging.info("Processing {} {}".format(bucket, key))

            tmpkey = key.replace('/', '')
            download_path = '/tmp/{}{}'.format(uuid.uuid4(), tmpkey)
            upload_path = '/tmp/resized-{}'.format(tmpkey)
            self.s3_client.download_file(bucket, key, download_path)
            resize_image(download_path, upload_path)
            self.s3_client.upload_file(upload_path, '{}-resized'.format(bucket), 'resized-{}'.format(key))

        logging.info("At the end!") 
