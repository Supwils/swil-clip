import { useCallback, useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { ClipboardPanel } from "@/components/ClipboardPanel";
import { useClipboardHistory } from "@/hooks/useClipboardHistory";
import { useClipboardActions } from "@/hooks/useClipboardActions";
import type { ClipItem } from "@/types/clipboard";
import { QUICK_PASTE_LIMIT } from "@/constants";

export function App(): React.ReactElement {
  const { items, refresh } = useClipboardHistory();
  const { pasteItem, deleteItem, clearAll, pinItem } = useClipboardActions(refresh);
  const [showCount, setShowCount] = useState(0);

  const handlePaste = useCallback(
    (item: ClipItem) => {
      pasteItem(item);
    },
    [pasteItem],
  );

  const handleDelete = useCallback(
    (id: string) => {
      deleteItem(id);
    },
    [deleteItem],
  );

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        getCurrentWindow().hide();
        return;
      }

      if (event.altKey && !event.metaKey && !event.shiftKey && !event.ctrlKey) {
        const num = parseInt(event.key, 10);
        if (num >= 1 && num <= QUICK_PASTE_LIMIT) {
          const target = items[num - 1];
          if (target) {
            event.preventDefault();
            pasteItem(target);
          }
        }
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [items, pasteItem]);

  useEffect(() => {
    const appWindow = getCurrentWindow();
    const unlisten = appWindow.onFocusChanged(({ payload: focused }) => {
      if (focused) {
        setShowCount((c) => c + 1);
        refresh();
      } else {
        appWindow.hide();
      }
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, [refresh]);

  return (
    <div className="app-shell">
      <ClipboardPanel
        key={showCount}
        items={items}
        onPaste={handlePaste}
        onDelete={handleDelete}
        onClearAll={clearAll}
        onPin={pinItem}
      />
    </div>
  );
}
