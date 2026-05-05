import { buildConnectedOutputsIndex } from "../../../lib/workflows/graph-constants";

const HANDLE_LENGTH = 30;
const HANDLE_TOTAL = HANDLE_LENGTH + 14;
const SOCKET_RADIUS = 5;

function buildHandleEntry(
  nodeEntry,
  nodeId,
  startPos,
  toRight,
  outputKey,
  areaElement
) {
  // SVG positioned at button's canvas location so foreignObject x is always positive (outside viewport = no pointer events).
  // Paths start at socket edge (not center) to avoid drawing inside the socket circle.
  if (toRight) {
    return {
      areaElement,
      nodeClientId: nodeId,
      outputKey,
      svgLeft: startPos.x,
      svgTop: startPos.y - 7,
      pathD: `M ${SOCKET_RADIUS} 7 L ${HANDLE_LENGTH} 7`,
      buttonX: HANDLE_LENGTH,
      buttonY: 0,
    };
  } else {
    return {
      areaElement,
      nodeClientId: nodeId,
      outputKey,
      svgLeft: startPos.x - HANDLE_TOTAL,
      svgTop: startPos.y - 7,
      pathD: `M ${HANDLE_TOTAL - SOCKET_RADIUS} 7 L 14 7`,
      buttonX: 0,
      buttonY: 0,
    };
  }
}

function updateHandles(
  entries,
  nodeEntries,
  connectionElements,
  getSocketCanvasPos,
  dirtyNodeIds,
  { buildIndex, getHandles }
) {
  const connectedIndex = buildIndex(
    [...connectionElements.values()]
      .filter((e) => !e.payload?.isPseudo)
      .map((e) => e.payload)
  );
  const activeHandleKeys = new Set();
  const promises = [];

  for (const [nodeId, nodeEntry] of nodeEntries) {
    for (const spec of getHandles(nodeId, nodeEntry.node, connectedIndex)) {
      if (spec.connected) {
        entries.delete(spec.handleKey);
        continue;
      }

      activeHandleKeys.add(spec.handleKey);

      if (dirtyNodeIds && !dirtyNodeIds.has(nodeId)) {
        continue;
      }

      promises.push(
        (async () => {
          const pos = await getSocketCanvasPos(
            nodeId,
            spec.side,
            spec.socketKey
          );
          if (pos) {
            entries.set(
              spec.handleKey,
              buildHandleEntry(
                nodeEntry,
                nodeId,
                pos,
                spec.toRight,
                spec.outputKey,
                spec.areaElement ?? nodeEntry.element.parentElement
              )
            );
          }
        })()
      );
    }
  }

  return Promise.all(promises).then(() => {
    for (const key of entries.keys()) {
      if (!activeHandleKeys.has(key)) {
        entries.delete(key);
      }
    }
  });
}

export function updateOutputHandles(
  entries,
  nodeEntries,
  connectionElements,
  getSocketCanvasPos,
  dirtyNodeIds
) {
  return updateHandles(
    entries,
    nodeEntries,
    connectionElements,
    getSocketCanvasPos,
    dirtyNodeIds,
    {
      buildIndex: buildConnectedOutputsIndex,
      getHandles(nodeId, node, connectedOutputs) {
        return Object.keys(node.outputs)
          .filter((key) => key !== "loop")
          .map((outputKey) => ({
            handleKey: `${nodeId}:${outputKey}`,
            connected: connectedOutputs.get(nodeId)?.has(outputKey) ?? false,
            side: "output",
            socketKey: outputKey,
            toRight: true,
            outputKey,
          }));
      },
    }
  );
}

export function updateInputHandles(
  entries,
  nodeEntries,
  connectionElements,
  getSocketCanvasPos,
  dirtyNodeIds,
  graphIndex,
  areaContentElement
) {
  return updateHandles(
    entries,
    nodeEntries,
    connectionElements,
    getSocketCanvasPos,
    dirtyNodeIds,
    {
      buildIndex(connections) {
        const connected = new Set();
        for (const conn of connections) {
          if (
            conn.source !== conn.target &&
            graphIndex.loopOwnerByNodeId.get(conn.source) !== conn.target
          ) {
            connected.add(conn.target);
          }
        }
        return connected;
      },
      getHandles(nodeId, node, connectedInputs) {
        if (!Object.keys(node.inputs).length) {
          return [];
        }
        return [
          {
            handleKey: nodeId,
            connected: connectedInputs.has(nodeId),
            side: "input",
            socketKey: "input",
            toRight: false,
            outputKey: null,
            areaElement: areaContentElement,
          },
        ];
      },
    }
  );
}
