"""Sending text messages.

Today only test mode exists: the SMS is written to the backend log.
To go live, replace send_sms() with a call to the chosen provider
(MSG91, Fast2SMS, Twilio...). Nothing else needs to change.

The message (which holds the OTP) is written to the log ONLY in test mode
(QBOX_OTP_EXPOSE=true). Otherwise the log never holds a code: anyone who can
read server logs must not be able to log in as somebody else.
"""

import logging

from app.config import get_settings

log = logging.getLogger("qbox.sms")


def send_sms(mobile: str, message: str) -> None:
    if get_settings().otp_expose:
        log.info("[TEST SMS] to +91 %s: %s", mobile, message)
        return
    log.error("SMS to +91 %s not sent: no SMS provider is connected (see app/auth/sms.py)", _masked(mobile))


def _masked(mobile: str) -> str:
    """98******10: enough to tell numbers apart in the log, not to read them."""
    return f"{mobile[:2]}{'*' * max(0, len(mobile) - 4)}{mobile[-2:]}" if len(mobile) > 4 else "****"
