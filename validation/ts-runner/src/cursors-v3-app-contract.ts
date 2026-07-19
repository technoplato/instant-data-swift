export const cursorsV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/cursors.tsx",
    component: "client/packages/react/src/Cursors.tsx",
  },
  room: {
    type: "cursors-example",
    id: "123",
    spaceID: "cursors-space-default--cursors-example-123",
  },
  fixtures: {
    swift: {
      x: 150,
      y: 90,
      xPercent: 25,
      yPercent: 40,
      color: "#123456",
    },
    typeScript: {
      x: 300,
      y: 200,
      xPercent: 75,
      yPercent: 60,
      color: "#654321",
    },
  },
  compilerWarningCount: 0,
} as const;

export interface CursorsV3Cursor {
  x: number;
  y: number;
  xPercent: number;
  yPercent: number;
  color: string;
}

export interface CursorsV3Point {
  clientX: number;
  clientY: number;
}

export interface CursorsV3Frame {
  left: number;
  top: number;
  width: number;
  height: number;
}

export function cursorForPoint(
  point: CursorsV3Point,
  frame: CursorsV3Frame,
  color: string,
): CursorsV3Cursor {
  return {
    x: point.clientX,
    y: point.clientY,
    xPercent: ((point.clientX - frame.left) / frame.width) * 100,
    yPercent: ((point.clientY - frame.top) / frame.height) * 100,
    color,
  };
}

export function darkCursorColor(red: number, green: number, blue: number): string {
  return `#${[red, green, blue]
    .map((component) => component.toString(16).padStart(2, "0"))
    .join("")}`;
}
