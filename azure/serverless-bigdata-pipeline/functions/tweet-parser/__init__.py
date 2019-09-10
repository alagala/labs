import logging

import azure.functions as func

# Import the Python specified in requirements.txt
import json
import preprocessor as p

def main(event: func.EventHubEvent) -> str:
    text = ""
    try:
        tweet = json.loads(event.get_body().decode('utf-8'))
        text = tweet[0]["text"]
        logging.info('Python EventHub trigger processed a tweet: %s', text)

    except KeyError:
        logging.error('Error parsing tweet.')
        pass
    
    else:
        # Tokenize the tweet and outputs it.
        tokenized = p.tokenize(text)
        logging.info('Tweet tokenized into: %s', tokenized)
        return tokenized
