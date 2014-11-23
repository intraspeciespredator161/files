/*
 * DndHandler.vala
 * 
 * Copyright 2014 jeremy <jeremy@jeremy-MM061>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 * 
 * 
 */

namespace FM {
    public class DndHandler : GLib.Object {
        Gdk.DragAction chosen = Gdk.DragAction.DEFAULT;

        public DndHandler () {}

        public bool dnd_perform (Gtk.Widget widget,
                                 GOF.File drop_target,
                                 GLib.List<GLib.File> drop_file_list,
                                 Gdk.DragAction action) {

            if (drop_target.is_folder ()) {
                Marlin.FileOperations.copy_move (drop_file_list,
                                                 null,
                                                 drop_target.get_target_location (),
                                                 action,
                                                 widget,
                                                 (void*)dnd_done,
                                                 null);
                return true;
            } else if (drop_target.is_executable ()) {
                GLib.Error error;
                if (!drop_target.execute (widget.get_screen (), drop_file_list, out error)) {
                    Eel.show_error_dialog (_("Failed to execute \"%s\"").printf (drop_target.get_display_name ()),
                                           error.message,
                                           null);
                    return false;
                } else
                    return true;
            }
            return false;
        }

        private void dnd_done (GLib.List<GLib.File> files, void* data) {}

        public Gdk.DragAction? drag_drop_action_ask (Gtk.Widget dest_widget,
                                                      Gtk.ApplicationWindow win,
                                                      Gdk.DragAction possible_actions) {
            this.chosen = Gdk.DragAction.DEFAULT;
            add_action (win);
            var ask_menu = build_menu (possible_actions);
            ask_menu.set_screen (dest_widget.get_screen ());
            ask_menu.show_all ();
            var loop = new GLib.MainLoop (null, false);

            ask_menu.deactivate.connect (() => {
                if (loop.is_running ())
                    loop.quit ();

                remove_action (win);
            });

            ask_menu.popup (null, null, null, 0, Gdk.CURRENT_TIME);
            loop.run ();
            Gtk.grab_remove (ask_menu);

            return this.chosen;
        }

        private void add_action (Gtk.ApplicationWindow win) {
            var action = new GLib.SimpleAction ("choice", GLib.VariantType.STRING);
            action.activate.connect (this.on_choice);
            
            win.add_action (action);
        }

        private void remove_action (Gtk.ApplicationWindow win) {
            win.remove_action ("choice");
        }

        private Gtk.Menu build_menu (Gdk.DragAction possible_actions) {
            var menu = new Gtk.Menu ();

            build_and_append_menu_item (menu, _("Move Here"), Gdk.DragAction.MOVE, possible_actions);
            build_and_append_menu_item (menu, _("Copy Here"), Gdk.DragAction.COPY, possible_actions);
            build_and_append_menu_item (menu, _("Link Here"), Gdk.DragAction.LINK, possible_actions);

            menu.append (new Gtk.SeparatorMenuItem ());
            menu.append (new Gtk.MenuItem.with_label (_("Cancel")));

            return menu;
        }

        private void build_and_append_menu_item (Gtk.Menu menu, string label, Gdk.DragAction? action, Gdk.DragAction possible_actions) {
            if ((possible_actions & action) != 0) {
                var item = new Gtk.MenuItem.with_label (label);

                item.activate.connect (() => {
                    this.chosen = action;
                });

                menu.append (item);
            }
        }

        public void on_choice (GLib.Variant? param) {
            if (param == null || !param.is_of_type (GLib.VariantType.STRING)) {
                critical ("Invalid variant type in DndHandler Menu");
                return;
            }

            string choice = param.get_string ();

            switch (choice) {
                case "move":
                    this.chosen = Gdk.DragAction.MOVE;
                    break;
                case "copy":
                    this.chosen = Gdk.DragAction.COPY;
                    break;
                case "link":
                    this.chosen = Gdk.DragAction.LINK;
                    break;
                case "background": /* not implemented yet */
                case "cancel":
                default:
                    this.chosen = Gdk.DragAction.DEFAULT;
                    break;
            }
        }

        public string? get_source_filename (Gdk.DragContext context) {
            uchar []? data = null;
            Gdk.Atom property_name = Gdk.Atom.intern_static_string ("XdndDirectSave0");
            Gdk.Atom property_type = Gdk.Atom.intern_static_string ("text/plain");

            bool exists = Gdk.property_get (context.get_source_window (),
                                            property_name,
                                            property_type,
                                            0, /* offset into property to start getting */
                                            1024, /* max bytes of data to retrieve */
                                            0, /* do not delete after retrieving */
                                            null, null, /* actual property type and format got disregarded */
                                            out data
                                           );
 
            if (exists && data != null) {
                string name = data_to_string (data);
                if (GLib.Path.DIR_SEPARATOR.to_string () in name) {
                    warning ("invalid source filename");
                    return null; /* not a valid filename */
                } else
                    return name;
            } else {
                warning ("source file does not exist");
                return null;
            }
        }

        public void set_source_uri (Gdk.DragContext context, string uri) {
            debug ("DNDHANDLER: set source uri to %s", uri);
            Gdk.Atom property_name = Gdk.Atom.intern_static_string ("XdndDirectSave0");
            Gdk.Atom property_type = Gdk.Atom.intern_static_string ("text/plain");

            Gdk.property_change (context.get_source_window (),
                                 property_name,
                                 property_type,
                                 8,
                                 Gdk.PropMode.REPLACE,
                                 uri.data,
                                 uri.length);
        }

        public bool handle_xdnddirectsave (Gdk.DragContext context,
                                           GOF.File drop_target,
                                           Gtk.SelectionData selection) {
            bool success = false;

            if (selection.get_length ()  == 1 && selection.get_format () == 8) {
                uchar result = selection.get_data ()[0];

                switch (result) {
                    case 'F':
                        /* No fallback for XdndDirectSave stage (3), result "F" ("Failed") yet */
                        break;
                    case 'S':
                        /* XdndDirectSave "Success" */
                        success = true;
                        break;
                    default:
                        warning ("Unhandled XdndDirectSave result %s", result.to_string ());
                        break;
                }
            }

            if (!success)
                set_source_uri (context, "");

            return success;
        }

        public bool handle_netscape_url (Gdk.DragContext context, GOF.File drop_target, Gtk.SelectionData selection) {
            string [] parts = (selection.get_text ()).split ("\n");

            /* _NETSCAPE_URL looks like this: "$URL\n$TITLE" - should be 2 parts */
            if (parts.length != 2)
                return false;

            /* NETSCAPE URLs are not currently handled.  No current bug reports */
            return false;
        }

        public bool handle_file_drag_actions (Gtk.Widget dest_widget,
                                              Gtk.ApplicationWindow win,
                                              Gdk.DragContext context,
                                              GOF.File drop_target,
                                              GLib.List<GLib.File> drop_file_list,
                                              Gdk.DragAction possible_actions,
                                              Gdk.DragAction suggested_action,
                                              uint32 timestamp) {
            bool success = false;
            Gdk.DragAction action = suggested_action;

            if ((possible_actions & Gdk.DragAction.ASK) != 0)
                action = drag_drop_action_ask (dest_widget, win, possible_actions);

            if (action != Gdk.DragAction.DEFAULT) {
                success = dnd_perform (dest_widget,
                                       drop_target,
                                       drop_file_list,
                                       action);
            }
            return success;
        }


        public bool selection_data_is_uri_list (Gtk.SelectionData selection_data, uint info, out string? text) {
            text = null;

            if (info == AbstractDirectoryView.TargetType.TEXT_URI_LIST &&
                selection_data.get_format () == 8 &&
                selection_data.get_length () > 0) {

                text = data_to_string (selection_data.get_data_with_length ());
            }
            debug ("DNDHANDLER selection data is uri list returning %s", (text != null).to_string ());
            return (text != null);
        }

        private string data_to_string (uchar [] cdata) {
            var sb = new StringBuilder ("");

            foreach (uchar u in cdata)
                sb.append_c ((char)u);

            return sb.str;
        }
    }
}
