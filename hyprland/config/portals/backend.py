#!/usr/bin/env python3
"""D-Bus AppChooser and Access backend; Quickshell owns the dialog UI."""
import argparse
import signal
import sys
from gi.repository import Gio, GLib

from common import Dialog, app_choices, app_metadata, label

NAME = 'org.freedesktop.impl.portal.desktop.dotfiles'
PATH = '/org/freedesktop/portal/desktop'
PREFIX = 'org.freedesktop.impl.portal.'
XML = '''<node>
<interface name="org.freedesktop.impl.portal.AppChooser">
 <property name="version" type="u" access="read"/>
 <method name="ChooseApplication">
  <arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
  <arg type="as" direction="in"/><arg type="a{sv}" direction="in"/>
  <arg type="u" direction="out"/><arg type="a{sv}" direction="out"/>
 </method>
 <method name="UpdateChoices"><arg type="o" direction="in"/><arg type="as" direction="in"/></method>
</interface>
<interface name="org.freedesktop.impl.portal.Access">
 <property name="version" type="u" access="read"/>
 <method name="AccessDialog">
  <arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
  <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
  <arg type="a{sv}" direction="in"/><arg type="u" direction="out"/><arg type="a{sv}" direction="out"/>
 </method>
</interface>
</node>'''
REQUEST = Gio.DBusNodeInfo.new_for_xml('''<node><interface name="org.freedesktop.impl.portal.Request">
 <method name="Close"/></interface></node>''').interfaces[0]


def access_choices(options):
    result = []
    for identity, name, values, selected in options.get('choices', []):
        if any(choice['id'] == identity for choice in result):
            raise ValueError('Duplicate choice ID')
        allowed = [value[0] for value in values] if values else ['false', 'true']
        if selected not in allowed:
            selected = allowed[0]
        result.append({'id': identity, 'name': name, 'values': [{'id': v, 'name': n} for v, n in values],
                       'selected': selected})
    return result


def response_values(data, result):
    response = result.get('response', 2)
    if type(response) is not int or response not in (0, 1, 2):
        return 2, {}
    if response != 0:
        return response, {}
    if data['kind'] == 'apps':
        choice = result.get('choice')
        if not isinstance(choice, str) or choice not in {app['id'] for app in data['apps']}:
            return 2, {}
        return 0, {'choice': GLib.Variant('s', choice.removesuffix('.desktop'))}
    selected = result.get('choices', {})
    if not isinstance(selected, dict):
        return 2, {}
    values = []
    for choice in data['choices']:
        value = selected.get(choice['id'], choice['selected'])
        allowed = [item['id'] for item in choice['values']] if choice['values'] else ['false', 'true']
        if value not in allowed:
            return 2, {}
        values.append((choice['id'], value))
    return 0, {'choices': GLib.Variant('a(ss)', values)}


class Backend:
    def __init__(self, bus, testing=False):
        self.bus, self.testing = bus, testing
        self.pending = {}
        self.registrations = []
        for interface in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
            self.registrations.append(bus.register_object(PATH, interface, self.method, self.property, None))
        bus.signal_subscribe('org.freedesktop.DBus', 'org.freedesktop.DBus', 'NameOwnerChanged',
                             '/org/freedesktop/DBus', None, Gio.DBusSignalFlags.NONE, self.owner_changed)

    def property(self, connection, sender, path, interface, name):
        return GLib.Variant('u', 2 if interface == PREFIX + 'AppChooser' else 1)

    def authorized(self, sender):
        if self.testing:
            return True
        try:
            owner = self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                                       'GetNameOwner', GLib.Variant('(s)', ('org.freedesktop.portal.Desktop',)),
                                       GLib.VariantType.new('(s)'), Gio.DBusCallFlags.NONE, 1500, None).unpack()[0]
            return sender == owner
        except GLib.Error:
            return False

    def method(self, connection, sender, path, interface, method, parameters, invocation):
        if not self.authorized(sender):
            invocation.return_dbus_error('org.freedesktop.DBus.Error.AccessDenied', 'Only the portal frontend may request dialogs.')
            return
        try:
            args = parameters.unpack()
            handle = args[0]
            if method == 'UpdateChoices':
                pending = self.pending.get(handle)
                if pending and pending['sender'] == sender and pending['data']['kind'] == 'apps':
                    pending['data']['apps'] = app_choices(args[1])
                    pending['dialog'].update(pending['data'])
                invocation.return_value(None)
                return
            if handle in self.pending:
                raise ValueError('Request already exists')
            if len(self.pending) >= 16:
                raise ValueError('Too many pending requests')
            app_id, parent = args[1:3]
            options = args[-1]
            data = {'app': app_metadata(app_id), 'parent': parent, 'activationToken': options.get('activation_token', '')}
            if method == 'ChooseApplication':
                data.update(kind='apps', title='Open with', filename=options.get('filename', ''),
                            contentType=options.get('content_type', ''), apps=app_choices(args[3]))
            elif method == 'AccessDialog':
                data.update(kind='access', title=args[3], subtitle=args[4], body=args[5], choices=access_choices(options),
                            denyLabel=label(options.get('deny_label', 'Deny')), grantLabel=label(options.get('grant_label', 'Allow')))
            else:
                raise ValueError('Unknown method')
            dialog = Dialog(data)
            try:
                registration = self.bus.register_object(handle, REQUEST, self.close_request, None, None)
            except Exception:
                dialog.close()
                raise
            self.pending[handle] = {'sender': sender, 'invocation': invocation, 'data': data,
                                    'dialog': dialog, 'registration': registration}
            GLib.timeout_add(75, self.poll, handle)
        except (ValueError, OSError, GLib.Error) as error:
            invocation.return_dbus_error('org.freedesktop.portal.Error.Failed', str(error))

    def poll(self, handle):
        pending = self.pending.get(handle)
        if not pending:
            return False
        if pending['dialog'].process.poll() is None:
            return True
        self.finish(handle, pending['dialog'].result())
        return False

    def finish(self, handle, result):
        pending = self.pending.pop(handle, None)
        if not pending:
            return
        try:
            code, values = response_values(pending['data'], result)
            pending['invocation'].return_value(GLib.Variant('(ua{sv})', (code, values)))
        finally:
            self.bus.unregister_object(pending['registration'])
            pending['dialog'].close()

    def close_request(self, connection, sender, path, interface, method, parameters, invocation):
        pending = self.pending.get(path)
        if pending and sender != pending['sender']:
            invocation.return_dbus_error('org.freedesktop.DBus.Error.AccessDenied', 'Request belongs to another caller.')
            return
        self.finish(path, {'response': 2})
        invocation.return_value(None)

    def owner_changed(self, connection, sender, path, interface, signal, parameters):
        name, old, new = parameters.unpack()
        if old and not new:
            for handle, pending in list(self.pending.items()):
                if pending['sender'] == name:
                    self.finish(handle, {'response': 2})

    def stop(self):
        for handle in list(self.pending):
            self.finish(handle, {'response': 2})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', action='store_true', help='Allow direct calls on a private test bus')
    args = parser.parse_args()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    # Request synchronously so systemd readiness means the objects are exported.
    backend = Backend(bus, args.test)
    result = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
                           GLib.Variant('(su)', (NAME, 4)), GLib.VariantType.new('(u)'),
                           Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
    if result != 1:
        raise SystemExit('Portal backend already running')
    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])
    try:
        loop.run()
    finally:
        backend.stop()


if __name__ == '__main__':
    main()
