"""Profile photos.

- A shop's photo may be seen by anyone logged in who was given its ref (their
  shops, a shop they are about to pay). Other photos: only by their owner.
- Only plain JPEGs are kept. Everything that is not the picture itself (where it
  was taken, which phone) is removed, even if the app did not do it.
- A new photo gets a new ref, so a phone can keep the one it has for good.
"""

import base64
import binascii
import secrets

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import ProfilePhoto, Role, User
from app.ratelimit import limit_photos
from app.users.schemas import PhotoOut

MAX_BYTES = 300_000
MAX_SIDE = 1024

# The parts a picture needs: sizes, tables, and the two that say how colours are stored.
_FRAMES = {0xC0, 0xC1, 0xC2}
_KEPT = _FRAMES | {0xC4, 0xDB, 0xDD, 0xE0, 0xEE}


def ref_of(db: Session, user_id: int, role: Role) -> str | None:
    return db.scalar(select(ProfilePhoto.ref).where(ProfilePhoto.user_id == user_id, ProfilePhoto.role == role.value))


def set_photo(db: Session, user: User, role: Role, jpeg: str) -> None:
    _require(user, role)
    limit_photos(user.id)
    try:
        data = base64.b64decode(jpeg, validate=True)
    except (binascii.Error, ValueError):
        raise _bad() from None
    row = db.get(ProfilePhoto, (user.id, role.value))
    if row is None:
        row = ProfilePhoto(user_id=user.id, role=role.value)
        db.add(row)
    row.jpeg = clean_jpeg(data)
    row.ref = secrets.token_hex(16)
    try:
        db.commit()
    except IntegrityError:  # two at the same moment
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None


def remove_photo(db: Session, user: User, role: Role) -> None:
    _require(user, role)
    row = db.get(ProfilePhoto, (user.id, role.value))
    if row is not None:
        db.delete(row)
        db.commit()


def photo(db: Session, user: User, ref: str) -> PhotoOut:
    row = db.scalars(select(ProfilePhoto).where(ProfilePhoto.ref == ref)).first()
    if row is None or (row.user_id != user.id and row.role != Role.BUSINESS.value):
        raise ApiError(404, "PHOTO_NOT_FOUND", "This photo is not available")
    return PhotoOut(jpeg=base64.b64encode(row.jpeg).decode())


def clean_jpeg(data: bytes) -> bytes:
    """The same picture with only the parts it needs. Refuses anything else."""
    if len(data) > MAX_BYTES:
        raise ApiError(400, "BAD_PHOTO", "This photo is too big. Please choose another one")
    if data[:2] != b"\xff\xd8":
        raise _bad()
    out = bytearray(b"\xff\xd8")
    at, sized = 2, False
    while at + 4 <= len(data):
        if data[at] != 0xFF:
            raise _bad()
        marker = data[at + 1]
        if marker == 0xFF:  # filler
            at += 1
            continue
        length = int.from_bytes(data[at + 2:at + 4], "big")
        end = at + 2 + length
        if length < 2 or end > len(data):
            raise _bad()
        if marker in _FRAMES:
            if length < 8:
                raise _bad()
            high = int.from_bytes(data[at + 5:at + 7], "big")
            wide = int.from_bytes(data[at + 7:at + 9], "big")
            if not (0 < high <= MAX_SIDE and 0 < wide <= MAX_SIDE):
                raise ApiError(400, "BAD_PHOTO", "This photo is too big. Please choose another one")
            sized = True
        if marker == 0xDA:  # the picture itself, up to the end mark
            stop = data.rfind(b"\xff\xd9")
            if not sized or stop < end:
                raise _bad()
            out += data[at:stop + 2]
            return bytes(out)
        if marker in _KEPT:
            out += data[at:end]
        at = end
    raise _bad()


def _require(user: User, role: Role) -> None:
    if role.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _bad() -> ApiError:
    return ApiError(400, "BAD_PHOTO", "This photo could not be read. Please choose another one")
