"""Every error reaches the app in the same shape: {"code": "...", "message": "..."}.
Messages are written for shopkeepers, because the app shows them as-is."""

import logging

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

log = logging.getLogger("qbox")


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def _body(code: str, message: str) -> dict:
    return {"code": code, "message": message}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, exc: ApiError):
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message))

    @app.exception_handler(RequestValidationError)
    async def handle_validation(request: Request, exc: RequestValidationError):
        errors = exc.errors()
        message = "Some details are missing or invalid"
        if errors:
            first = errors[0]
            if first.get("type") == "json_invalid":
                message = "Request could not be read"
            elif first.get("type") != "missing":
                # Our own checks raise ValueError("..."); pydantic adds "Value error, " in front.
                message = str(first.get("msg", message)).removeprefix("Value error, ")
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content=_body("INVALID_INPUT", message))

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception):
        log.exception("Unexpected error")
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=_body("SERVER_ERROR", "Something went wrong. Please try again."),
        )
