#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["boto3", "botocore", "img2pdf"]
# ///

import boto3
from botocore.exceptions import ClientError
import img2pdf

# Initialize Bedrock client
client = boto3.client("bedrock-runtime", region_name="us-east-1")

# Set the correct model ID (Update this to your intended model, e.g., DeepSeek-R1 or Claude)
model_id = "us.deepseek.r1-v1:0" # Replace with your exact enabled Bedrock model ID

# Convert the image to a PDF in-memory so Bedrock can read it as a document
try:
    pdf_bytes = img2pdf.convert('image01.jpg')
except FileNotFoundError:
    print("ERROR: 'image01.jpg' not found in the local directory.")
    exit(1)

# Format the conversation structure using Bedrock's Converse API expectations
conversation = [
    {
        "role": "user",
        "content": [
            {
                "document": {
                    "name": "image_doc",       # Alphanumeric name only
                    "format": "pdf",           # PDFs are fully supported in the document block
                    "source": {
                        "bytes": pdf_bytes
                    }
                }
            },
            {
                "text": "What does this document contain? Please describe the contents."
            },
        ],
    }
]

try:
    # Send the request
    response = client.converse(
        modelId=model_id,
        messages=conversation,
        inferenceConfig={"maxTokens": 2000, "temperature": 0.3},
    )

    reasoning = ""
    response_text = ""

    # Safely extract content blocks
    for item in response["output"]["message"]["content"]:
        if "text" in item:
            response_text += item["text"]
        # Look for model reasoning/thinking blocks if supported by the model (like DeepSeek-R1)
        elif "reasoningContent" in item and "text" in item["reasoningContent"]:
            reasoning += item["reasoningContent"]["text"]

    if reasoning:
        print(f"\n=== Reasoning ===\n{reasoning}")
        
    print(f"\n=== Response ===\n{response_text}")

except ClientError as e:
    print(f"AWS Client Error: Can't invoke '{model_id}'.\nDetails: {e.response['Error']['Message']}")
except Exception as e:
    print(f"Unexpected Error: {e}")
    exit(1)