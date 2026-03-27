export type ClipType = "text" | "image";

export interface ClipItem {
  id: string;
  clipType: ClipType;
  content: string;
  preview: string;
  timestamp: number;
  appName?: string;
  imageWidth?: number;
  imageHeight?: number;
  imageFormat?: string;
}
