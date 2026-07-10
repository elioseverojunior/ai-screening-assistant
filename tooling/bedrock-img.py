#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["boto3", "botocore"]
# ///

# Send and process an image with NVIDIA Nemotron on Amazon Bedrock.

import boto3
from botocore.exceptions import ClientError

# Create a Bedrock Runtime client in the AWS Region you want to use.
client = boto3.client("bedrock-runtime", region_name="us-east-1")

# Set the model ID
model_id = "nvidia.nemotron-nano-12b-v2"

# Load the image
with open("image03.png", "rb") as file:
    image_bytes = file.read()

# Start a conversation with a user message containing BOTH the image and text blocks
conversation = [
    {
        "role": "user",
        "content": [
            {
                "image": {
                    "format": "png",  # Can be png, jpeg, gif, or webp
                    "source": {
                        "bytes": image_bytes
                    }
                }
            },
            {
                "text": "Check the content, and if it's a interview challenge, so, analyze the question[s] and answer them," + 
                "given the right alternative if it has alternative, them explain how you got the answer." + 
                "If it has a code snippet, or description to create the code with some scope, implement the code always using the best performance and secure practices." +
                "If none of the above context, just respond with a brief summary."
            },
        ],
    }
]

try:
    # Send the message to the model, using a basic inference configuration.
    response = client.converse(
        modelId=model_id,
        messages=conversation,
        inferenceConfig={"maxTokens": 2000, "temperature": 0.3},
    )

    # Extract and print the response text.
    reasoning, response_text = "", ""
    for item in response["output"]["message"]["content"]:
        for key, value in item.items():
            if key == "reasoningContent":
                reasoning = value.get("reasoningText", {}).get("text", "")
            elif key == "text":
                response_text = value

    if reasoning:
        print(f"\nReasoning:\n{reasoning}")
    print(f"\nResponse:\n{response_text}")

except (ClientError, Exception) as e:
    print(f"ERROR: Can't invoke '{model_id}'. Reason: {e}")
    exit(1)