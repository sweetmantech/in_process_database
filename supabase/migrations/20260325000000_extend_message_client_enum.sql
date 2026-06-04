ALTER TYPE message_client
ADD value if NOT EXISTS 'web';

ALTER TYPE message_client
ADD value if NOT EXISTS 'api';
