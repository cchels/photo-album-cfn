"""
Search-Photos Lambda
Invoked by API Gateway GET /search?q=…
1) Reads `q` from query string
2) Disambiguates via Lex V2 recognize_text
3) Constructs OpenSearch fuzzy-match query on labels
4) Returns list of S3 URLs + labels
"""

import os
import json
import boto3
import requests
from requests.auth import HTTPBasicAuth

# ─── Environment Variables ─────────────────────────────────────────────
REGION       = os.environ['REGION']
ES_ENDPOINT  = os.environ['ES_ENDPOINT']
ES_INDEX     = os.environ['ES_INDEX']
ES_USERNAME  = os.environ['ES_USERNAME']
ES_PASSWORD  = os.environ['ES_PASSWORD']
LEX_BOT_ID    = os.environ['BOT_ID']
LEX_ALIAS_ID  = os.environ['BOT_ALIAS_ID']
LEX_LOCALE    = os.environ['LOCALE_ID']

# ─── AWS Clients ────────────────────────────────────────────────────────
lex_client = boto3.client('lexv2-runtime', region_name=REGION)

def lambda_handler(event, context):
    """
    Handles GET /search via API Gateway Lambda Proxy Integration.
    Expects event['queryStringParameters']['q'] to contain the search text.
    """

    # 1) Extract raw query text "q"
    params = event.get('queryStringParameters') or {}
    raw_q = params.get('q', '').strip()
    if not raw_q:
        return _response(200, {"results": []})

    # 2) Disambiguate via Lex V2 RecognizeText
    try:
        lex_resp = lex_client.recognize_text(
            botId       = LEX_BOT_ID,
            botAliasId  = LEX_ALIAS_ID,
            localeId    = LEX_LOCALE,
            sessionId   = context.aws_request_id,
            text        = raw_q
        )
        slot = lex_resp['sessionState']['intent']['slots'].get('query1', {})
        term = slot.get('value', {}).get('interpretedValue', raw_q)
    except Exception as e:
        print(f"[WARN] Lex recognize_text failed: {e}")
        term = raw_q  # fallback to raw text

    # 3) Build OpenSearch fuzzy-match query
    es_query = {
        "query": {
            "match": {
                "labels": {
                    "query": term,
                    "fuzziness": "AUTO"
                }
            }
        }
    }

    # 4) Call OpenSearch _search endpoint
    url = f"{ES_ENDPOINT}/{ES_INDEX}/_search"
    auth = HTTPBasicAuth(ES_USERNAME, ES_PASSWORD)
    headers = {"Content-Type": "application/json"}

    try:
        es_resp = requests.get(url, auth=auth, headers=headers, json=es_query)
        es_resp.raise_for_status()
        hits = es_resp.json().get('hits', {}).get('hits', [])
    except Exception as e:
        print(f"[ERROR] OpenSearch query failed: {e}")
        return _response(500, {"error": "Search service unavailable"})

    # 5) Format results as list of {url, labels}
    results = []
    for h in hits:
        src = h.get('_source', {})
        bucket = src.get('bucket')
        key    = src.get('objectKey')
        if bucket and key:
            url = f"https://{bucket}.s3.amazonaws.com/{key}"
            results.append({"url": url, "labels": src.get('labels', [])})

    # 6) Return JSON array
    return _response(200, {"results": results})

def _response(status_code, body_dict):
    """
    Helper to build Lambda Proxy integration response.
    Adds CORS header to allow any origin.
    """
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body_dict)
    }
