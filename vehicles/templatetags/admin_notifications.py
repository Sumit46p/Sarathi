from django import template

register = template.Library()

@register.simple_tag(takes_context=True)
def admin_notification_count(context):
    request = context.get('request')
    if request and request.user.is_authenticated:
        from vehicles.models import Notification
        return Notification.objects.filter(user=request.user, is_read=False).count()
    return 0

@register.simple_tag(takes_context=True)
def admin_notifications(context, limit=10):
    request = context.get('request')
    if request and request.user.is_authenticated:
        from vehicles.models import Notification
        return Notification.objects.filter(user=request.user).order_by('-created_at')[:limit]
    return []
