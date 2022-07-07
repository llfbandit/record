#include "include/record_linux/record_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#define RECORD_LINUX_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), record_linux_plugin_get_type(), \
                              RecordLinuxPlugin))

struct _RecordLinuxPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(RecordLinuxPlugin, record_linux_plugin, g_object_get_type())

static void record_linux_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(record_linux_plugin_parent_class)->dispose(object);
}

static void record_linux_plugin_class_init(RecordLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = record_linux_plugin_dispose;
}

static void record_linux_plugin_init(RecordLinuxPlugin* self) {}

void record_linux_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  RecordLinuxPlugin* plugin = RECORD_LINUX_PLUGIN(
      g_object_new(record_linux_plugin_get_type(), nullptr));

  g_object_unref(plugin);
}
