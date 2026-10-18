"""Перевірка JWT (access token), виданого AWS Cognito, на стороні сервісу."""
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings

bearer = HTTPBearer(auto_error=False)


@lru_cache
def _jwks_client() -> jwt.PyJWKClient:
    return jwt.PyJWKClient(f"{get_settings().cognito_issuer}/.well-known/jwks.json")


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    s = get_settings()
    if not s.auth_enabled:
        return {"sub": "anonymous", "username": "anonymous"}
    if creds is None:
        raise _unauthorized("Missing bearer token")
    try:
        signing_key = _jwks_client().get_signing_key_from_jwt(creds.credentials)
        claims = jwt.decode(
            creds.credentials,
            signing_key.key,
            algorithms=["RS256"],
            issuer=s.cognito_issuer,
            options={"verify_aud": False},
        )
    except jwt.PyJWTError:
        raise _unauthorized("Invalid or expired token")
    if claims.get("token_use") != "access" or claims.get("client_id") != s.cognito_client_id:
        raise _unauthorized("Invalid token")
    return claims
