"""
Index-Photos Lambda
Triggered by S3 PUT events on the photo-storage bucket.
1) Reads new image key from event
2) Calls Rekognition to detect labels
3) Reads user-specified customLabels from S3 object metadata
4) Merges, deduplicates labels
5) Indexes document into OpenSearch 
"""

import os
import json
import datetime
import boto3
import requests
from requests.auth import HTTPBasicAuth

# ─── Environment Variables ─────────────────────────────────────────────
REGION      = os.environ['REGION']
ES_ENDPOINT = os.environ['ES_ENDPOINT']
ES_INDEX    = os.environ['ES_INDEX']
ES_USERNAME = os.environ['ES_USERNAME']
ES_PASSWORD = os.environ['ES_PASSWORD']

# ─── AWS Clients ────────────────────────────────────────────────────────
# Rekognition: detectLabels on images in S3
rek = boto3.client('rekognition', region_name=REGION)
# S3: read metadata from objects
s3  = boto3.client('s3', region_name=REGION)

def lambda_handler(event, context):
    """
    Main entrypoint for index-photos function.
    Expects an S3 PUT event in `event['Records'][0]`.
    """

    # 1) Extract bucket name and object key from event
    try:
        rec    = event['Records'][0]['s3']
        bucket = rec['bucket']['name']
        key    = rec['object']['key']
    except (KeyError, IndexError):
        raise ValueError("Event does not contain S3 PUT record")

    # 2) Call Rekognition.detect_labels to get auto-generated labels
    rek_resp = rek.detect_labels(
        Image={'S3Object': {'Bucket': bucket, 'Name': key}},
        MaxLabels=10,
        MinConfidence=75
    )
    auto_labels = [lbl['Name'] for lbl in rek_resp.get('Labels', [])]

    # 3) Retrieve custom labels from S3 metadata: x-amz-meta-customlabels
    head = s3.head_object(Bucket=bucket, Key=key)
    raw_meta = head.get('Metadata', {}).get('customlabels', '')
    custom_labels = [
        label.strip() for label in raw_meta.split(',')
        if label.strip()
    ]

    # 4) Combine and dedupe
    all_labels = list({*map(str.lower, auto_labels), *map(str.lower, custom_labels)})

    # 5) Build document to index
    doc = {
        "objectKey":        key,
        "bucket":           bucket,
        "createdTimestamp": datetime.datetime.utcnow().isoformat(),
        "labels":           all_labels
    }

    # 6) Index document into OpenSearch
    url = f"{ES_ENDPOINT}/{ES_INDEX}/_doc"
    auth = HTTPBasicAuth(ES_USERNAME, ES_PASSWORD)
    headers = {"Content-Type": "application/json"}
    resp = requests.post(url, auth=auth, headers=headers, data=json.dumps(doc))

    # 7) Check response status
    if resp.status_code not in (200, 201):
        print(f"[ERROR] OpenSearch indexing failed: {resp.status_code} {resp.text}")
        raise Exception(f"Indexing failed: {resp.status_code}")

    print(f"[SUCCESS] Indexed {key} with labels: {all_labels}")
    return {
        "statusCode": resp.status_code,
        "body":       json.dumps({"indexed": key})
    }
