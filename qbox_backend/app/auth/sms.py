"""Sending text messages.

Today only test mode exists: the SMS is written to the backend log.
To go live, replace send_sms() with a call to the chosen provider
(MSG91, Fast2SMS, Twilio...). Nothing else needs to change.
"""

import logging

log = logging.getLogger("qbox.sms")


def send_sms(mobile: str, message: str) -> None:
    log.info("[TEST SMS] to +91 %s: %s", mobile, message)
