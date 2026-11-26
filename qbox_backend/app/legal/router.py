"""Help, Privacy Policy and Terms: the same words as in the app (texts.json is copied
to the app's assets), as web pages for the app stores. No login needed."""

import json
from html import escape
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.config import get_settings
from app.schemas import CamelModel

router = APIRouter(tags=["Help and legal"])

TEXTS = json.loads((Path(__file__).parent / "texts.json").read_text(encoding="utf-8"))

_STYLE = ("body{font-family:system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px;line-height:1.6;"
          "color:#1c0e57;background:#f7f4ff}h1{font-size:28px}h2{font-size:18px;margin-top:28px}"
          "p{margin:6px 0}small{color:#5c5872}")


class InfoOut(CamelModel):
    """How to reach QBOX. Empty = not set yet."""

    support_name: str | None
    support_phone: str | None
    support_email: str | None
    # The app must be at least this build (0 = any); where to get it.
    min_build: int
    update_url: str | None


@router.get("/api/info", response_model=InfoOut, summary="How to reach QBOX")
def info():
    s = get_settings()
    return InfoOut(support_name=s.support_name or None, support_phone=s.support_phone or None,
                   support_email=s.support_email or None, min_build=s.app_min_build,
                   update_url=s.app_update_url or None)


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
def privacy():
    return _page("privacy")


@router.get("/terms", response_class=HTMLResponse, include_in_schema=False)
def terms():
    return _page("terms")


@router.get("/delete-account", response_class=HTMLResponse, include_in_schema=False)
def delete_account():
    """The page the Play Store asks for: how to delete without guessing."""
    body = "".join(f"<p>{escape(t)}</p>" for t in (
        "In the QBOX app: open your profile picture, then Profile, then Delete my account. Enter your PIN. "
        "It is done at once and cannot be undone.",
        "Deleted: your details, photos, PIN, calendar, notes, lists, expenses, stock, products, UPI IDs and payment keys.",
        "Kept, without your private details: a shop's udhaar lines, payments, and what a shop and a supplier shared, "
        "because they are also the other person's record.",
        "No phone with QBOX any more? Write to us from the mobile number of the account.",
    ))
    return _html("Delete your QBOX account", body + _contact())


def _page(key: str) -> str:
    text = TEXTS[key]
    body = f"<small>Last changed: {escape(text['updated'])}</small>"
    for heading, lines in text["sections"]:
        body += f"<h2>{escape(heading)}</h2>" + "".join(f"<p>{escape(line)}</p>" for line in lines)
    return _html(text["title"], body + _contact())


def _contact() -> str:
    s = get_settings()
    parts = [escape(x) for x in (s.support_name, s.support_phone, s.support_email) if x]
    return f"<h2>Contact</h2><p>{', '.join(parts)}</p>" if parts else ""


def _html(title: str, body: str) -> str:
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(title)} - QBOX</title>'
            f"<style>{_STYLE}</style></head><body><h1>{escape(title)}</h1>{body}</body></html>")
