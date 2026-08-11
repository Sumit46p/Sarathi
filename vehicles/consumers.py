import json
from channels.generic.websocket import AsyncWebsocketConsumer
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import UntypedToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from django.contrib.auth import get_user_model

User = get_user_model()


@database_sync_to_async
def get_user_from_token(token):
    try:
        validated_token = UntypedToken(token)
        user = User.objects.get(id=validated_token['user_id'])
        return user
    except (InvalidToken, TokenError, User.DoesNotExist):
        return AnonymousUser()


from accounts.models import get_organization_name

@database_sync_to_async
def get_user_org_name(user):
    try:
        org_name = get_organization_name()
        if org_name and org_name != 'Default Org':
            import re
            return re.sub(r'[^a-zA-Z0-9_\-]', '_', org_name.lower())
    except Exception:
        pass
    return "default_org"


class JWTAuthMiddleware:
    """
    Custom middleware to authenticate WebSocket connections via a JWT token
    passed in the query string: ?token=<jwt>
    """
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        query_string = scope.get('query_string', b'').decode('utf-8')
        query_params = parse_qs(query_string)
        token = query_params.get('token', [None])[0]

        if token:
            scope['user'] = await get_user_from_token(token)
        else:
            scope['user'] = AnonymousUser()

        return await self.app(scope, receive, send)


class NotificationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        user = self.scope['user']
        if user.is_anonymous:
            await self.close(code=4001)
            return

        self.groups_joined = []

        # 1. Driver-specific group (for personal notifications)
        driver_group = f'user_notifications_{user.id}'
        await self.channel_layer.group_add(driver_group, self.channel_name)
        self.groups_joined.append(driver_group)

        # 2. Organization-wide group (for admin dashboard alerts)
        org_name = await get_user_org_name(user)
        org_group = f'org_notifications_{org_name}'
        await self.channel_layer.group_add(org_group, self.channel_name)
        self.groups_joined.append(org_group)

        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, 'groups_joined'):
            for group in self.groups_joined:
                await self.channel_layer.group_discard(
                    group,
                    self.channel_name
                )

    async def send_notification(self, event):
        """
        Called when a 'send_notification' message is sent to the group.
        """
        payload = event['payload']
        await self.send(text_data=json.dumps(payload))
