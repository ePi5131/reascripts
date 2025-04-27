--[[
@metapackage
@name midi2item
@author ePi
@version 2.0preview
@provides
  [nomain] _midi2item_common.lua > ..
  [main] ePi_midi2item (Configure).lua > ..
  [main] ePi_midi2item.lua > ..
  [main] ePi_midi2item (Drum).lua > ..
  [main] ePi_midi2item - Select configurated tracks.lua > ..
@changelog
  ReaPack対応
  MIDIチャンネルに対応
  ピッチベンドに対応
  生成したトラックに名前を付ける機能を追加
  子トラックではなく新しいトラックに生成することとした
  柔軟な設定を行うためのスクリプトを追加
@about
  midi2itemは、MIDIアイテムのノーツをアイテムのピッチ情報へと変換するものです。
]]
