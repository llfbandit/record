import 'package:js/js.dart';

import 'js_interop/core.dart';

@JS('jsFixWebmDuration')
external dynamic fixWebmDuration(Blob blob, num duration, dynamic options);

String jsFixWebmDurationContentId() => 'fix-webm-duration';

String jsFixWebmDurationContent() {
  return 'window.jsFixWebmDuration=function(){var e={172351395:{name:"EBML",type:"Container"},646:{name:"EBMLVersion",type:"Uint"},759:{name:"EBMLReadVersion",type:"Uint"},754:{name:"EBMLMaxIDLength",type:"Uint"},755:{name:"EBMLMaxSizeLength",type:"Uint"},642:{name:"DocType",type:"String"},647:{name:"DocTypeVersion",type:"Uint"},645:{name:"DocTypeReadVersion",type:"Uint"},108:{name:"Void",type:"Binary"},63:{name:"CRC-32",type:"Binary"},190023271:{name:"SignatureSlot",type:"Container"},16010:{name:"SignatureAlgo",type:"Uint"},16026:{name:"SignatureHash",type:"Uint"},16037:{name:"SignaturePublicKey",type:"Binary"},16053:{name:"Signature",type:"Binary"},15963:{name:"SignatureElements",type:"Container"},15995:{name:"SignatureElementList",type:"Container"},9522:{name:"SignedElement",type:"Binary"},139690087:{name:"Segment",type:"Container"},21863284:{name:"SeekHead",type:"Container"},3515:{name:"Seek",type:"Container"},5035:{name:"SeekID",type:"Binary"},5036:{name:"SeekPosition",type:"Uint"},88713574:{name:"Info",type:"Container"},13220:{name:"SegmentUID",type:"Binary"},13188:{name:"SegmentFilename",type:"String"},1882403:{name:"PrevUID",type:"Binary"},1868715:{name:"PrevFilename",type:"String"},2013475:{name:"NextUID",type:"Binary"},1999803:{name:"NextFilename",type:"String"},1092:{name:"SegmentFamily",type:"Binary"},10532:{name:"ChapterTranslate",type:"Container"},10748:{name:"ChapterTranslateEditionUID",type:"Uint"},10687:{name:"ChapterTranslateCodec",type:"Uint"},10661:{name:"ChapterTranslateID",type:"Binary"},710577:{name:"TimecodeScale",type:"Uint"},1161:{name:"Duration",type:"Float"},1121:{name:"DateUTC",type:"Date"},15273:{name:"Title",type:"String"},3456:{name:"MuxingApp",type:"String"},5953:{name:"WritingApp",type:"String"},103:{name:"Timecode",type:"Uint"},6228:{name:"SilentTracks",type:"Container"},6359:{name:"SilentTrackNumber",type:"Uint"},39:{name:"Position",type:"Uint"},43:{name:"PrevSize",type:"Uint"},35:{name:"SimpleBlock",type:"Binary"},32:{name:"BlockGroup",type:"Container"},33:{name:"Block",type:"Binary"},34:{name:"BlockVirtual",type:"Binary"},13729:{name:"BlockAdditions",type:"Container"},38:{name:"BlockMore",type:"Container"},110:{name:"BlockAddID",type:"Uint"},37:{name:"BlockAdditional",type:"Binary"},27:{name:"BlockDuration",type:"Uint"},122:{name:"ReferencePriority",type:"Uint"},123:{name:"ReferenceBlock",type:"Int"},125:{name:"ReferenceVirtual",type:"Int"},36:{name:"CodecState",type:"Binary"},13730:{name:"DiscardPadding",type:"Int"},14:{name:"Slices",type:"Container"},104:{name:"TimeSlice",type:"Container"},76:{name:"LaceNumber",type:"Uint"},77:{name:"FrameNumber",type:"Uint"},75:{name:"BlockAdditionID",type:"Uint"},78:{name:"Delay",type:"Uint"},79:{name:"SliceDuration",type:"Uint"},72:{name:"ReferenceFrame",type:"Container"},73:{name:"ReferenceOffset",type:"Uint"},74:{name:"ReferenceTimeCode",type:"Uint"},47:{name:"EncryptedBlock",type:"Binary"},106212971:{name:"Tracks",type:"Container"},46:{name:"TrackEntry",type:"Container"},87:{name:"TrackNumber",type:"Uint"},13253:{name:"TrackUID",type:"Uint"},3:{name:"TrackType",type:"Uint"},57:{name:"FlagEnabled",type:"Uint"},8:{name:"FlagDefault",type:"Uint"},5546:{name:"FlagForced",type:"Uint"},28:{name:"FlagLacing",type:"Uint"},11751:{name:"MinCache",type:"Uint"},11768:{name:"MaxCache",type:"Uint"},254851:{name:"DefaultDuration",type:"Uint"},216698:{name:"DefaultDecodedFieldDuration",type:"Uint"},209231:{name:"TrackTimecodeScale",type:"Float"},4991:{name:"TrackOffset",type:"Int"},5614:{name:"MaxBlockAdditionID",type:"Uint"},4974:{name:"Name",type:"String"},177564:{name:"Language",type:"String"},6:{name:"CodecID",type:"String"},9122:{name:"CodecPrivate",type:"Binary"},362120:{name:"CodecName",type:"String"},13382:{name:"AttachmentLink",type:"Uint"},1742487:{name:"CodecSettings",type:"String"},1785920:{name:"CodecInfoURL",type:"String"},438848:{name:"CodecDownloadURL",type:"String"},42:{name:"CodecDecodeAll",type:"Uint"},12203:{name:"TrackOverlay",type:"Uint"},5802:{name:"CodecDelay",type:"Uint"},5819:{name:"SeekPreRoll",type:"Uint"},9764:{name:"TrackTranslate",type:"Container"},9980:{name:"TrackTranslateEditionUID",type:"Uint"},9919:{name:"TrackTranslateCodec",type:"Uint"},9893:{name:"TrackTranslateTrackID",type:"Binary"},96:{name:"Video",type:"Container"},26:{name:"FlagInterlaced",type:"Uint"},5048:{name:"StereoMode",type:"Uint"},5056:{name:"AlphaMode",type:"Uint"},5049:{name:"OldStereoMode",type:"Uint"},48:{name:"PixelWidth",type:"Uint"},58:{name:"PixelHeight",type:"Uint"},5290:{name:"PixelCropBottom",type:"Uint"},5307:{name:"PixelCropTop",type:"Uint"},5324:{name:"PixelCropLeft",type:"Uint"},5341:{name:"PixelCropRight",type:"Uint"},5296:{name:"DisplayWidth",type:"Uint"},5306:{name:"DisplayHeight",type:"Uint"},5298:{name:"DisplayUnit",type:"Uint"},5299:{name:"AspectRatioType",type:"Uint"},963876:{name:"ColourSpace",type:"Binary"},1029411:{name:"GammaValue",type:"Float"},230371:{name:"FrameRate",type:"Float"},97:{name:"Audio",type:"Container"},53:{name:"SamplingFrequency",type:"Float"},14517:{name:"OutputSamplingFrequency",type:"Float"},31:{name:"Channels",type:"Uint"},15739:{name:"ChannelPositions",type:"Binary"},8804:{name:"BitDepth",type:"Uint"},98:{name:"TrackOperation",type:"Container"},99:{name:"TrackCombinePlanes",type:"Container"},100:{name:"TrackPlane",type:"Container"},101:{name:"TrackPlaneUID",type:"Uint"},102:{name:"TrackPlaneType",type:"Uint"},105:{name:"TrackJoinBlocks",type:"Container"},109:{name:"TrackJoinUID",type:"Uint"},64:{name:"TrickTrackUID",type:"Uint"},65:{name:"TrickTrackSegmentUID",type:"Binary"},70:{name:"TrickTrackFlag",type:"Uint"},71:{name:"TrickMasterTrackUID",type:"Uint"},68:{name:"TrickMasterTrackSegmentUID",type:"Binary"},11648:{name:"ContentEncodings",type:"Container"},8768:{name:"ContentEncoding",type:"Container"},4145:{name:"ContentEncodingOrder",type:"Uint"},4146:{name:"ContentEncodingScope",type:"Uint"},4147:{name:"ContentEncodingType",type:"Uint"},4148:{name:"ContentCompression",type:"Container"},596:{name:"ContentCompAlgo",type:"Uint"},597:{name:"ContentCompSettings",type:"Binary"},4149:{name:"ContentEncryption",type:"Container"},2017:{name:"ContentEncAlgo",type:"Uint"},2018:{name:"ContentEncKeyID",type:"Binary"},2019:{name:"ContentSignature",type:"Binary"},2020:{name:"ContentSigKeyID",type:"Binary"},2021:{name:"ContentSigAlgo",type:"Uint"},2022:{name:"ContentSigHashAlgo",type:"Uint"},206814059:{name:"Cues",type:"Container"},59:{name:"CuePoint",type:"Container"},51:{name:"CueTime",type:"Uint"},55:{name:"CueTrackPositions",type:"Container"},119:{name:"CueTrack",type:"Uint"},113:{name:"CueClusterPosition",type:"Uint"},112:{name:"CueRelativePosition",type:"Uint"},50:{name:"CueDuration",type:"Uint"},4984:{name:"CueBlockNumber",type:"Uint"},106:{name:"CueCodecState",type:"Uint"},91:{name:"CueReference",type:"Container"},22:{name:"CueRefTime",type:"Uint"},23:{name:"CueRefCluster",type:"Uint"},4959:{name:"CueRefNumber",type:"Uint"},107:{name:"CueRefCodecState",type:"Uint"},155296873:{name:"Attachments",type:"Container"},8615:{name:"AttachedFile",type:"Container"},1662:{name:"FileDescription",type:"String"},1646:{name:"FileName",type:"String"},1632:{name:"FileMimeType",type:"String"},1628:{name:"FileData",type:"Binary"},1710:{name:"FileUID",type:"Uint"},1653:{name:"FileReferral",type:"Binary"},1633:{name:"FileUsedStartTime",type:"Uint"},1634:{name:"FileUsedEndTime",type:"Uint"},4433776:{name:"Chapters",type:"Container"},1465:{name:"EditionEntry",type:"Container"},1468:{name:"EditionUID",type:"Uint"},1469:{name:"EditionFlagHidden",type:"Uint"},1499:{name:"EditionFlagDefault",type:"Uint"},1501:{name:"EditionFlagOrdered",type:"Uint"},54:{name:"ChapterAtom",type:"Container"},13252:{name:"ChapterUID",type:"Uint"},5716:{name:"ChapterStringUID",type:"String"},17:{name:"ChapterTimeStart",type:"Uint"},18:{name:"ChapterTimeEnd",type:"Uint"},24:{name:"ChapterFlagHidden",type:"Uint"},1432:{name:"ChapterFlagEnabled",type:"Uint"},11879:{name:"ChapterSegmentUID",type:"Binary"},11964:{name:"ChapterSegmentEditionUID",type:"Uint"},9155:{name:"ChapterPhysicalEquiv",type:"Uint"},15:{name:"ChapterTrack",type:"Container"},9:{name:"ChapterTrackNumber",type:"Uint"},0:{name:"ChapterDisplay",type:"Container"},5:{name:"ChapString",type:"String"},892:{name:"ChapLanguage",type:"String"},894:{name:"ChapCountry",type:"String"},10564:{name:"ChapProcess",type:"Container"},10581:{name:"ChapProcessCodecID",type:"Uint"},1293:{name:"ChapProcessPrivate",type:"Binary"},10513:{name:"ChapProcessCommand",type:"Container"},10530:{name:"ChapProcessTime",type:"Uint"},10547:{name:"ChapProcessData",type:"Binary"},39109479:{name:"Tags",type:"Container"},13171:{name:"Tag",type:"Container"},9152:{name:"Targets",type:"Container"},10442:{name:"TargetTypeValue",type:"Uint"},9162:{name:"TargetType",type:"String"},9157:{name:"TagTrackUID",type:"Uint"},9161:{name:"TagEditionUID",type:"Uint"},9156:{name:"TagChapterUID",type:"Uint"},9158:{name:"TagAttachmentUID",type:"Uint"},10184:{name:"SimpleTag",type:"Container"},1443:{name:"TagName",type:"String"},1146:{name:"TagLanguage",type:"String"},1156:{name:"TagDefault",type:"Uint"},1159:{name:"TagString",type:"String"},1157:{name:"TagBinary",type:"Binary"}};function t(e,t){e.prototype=Object.create(t.prototype),e.prototype.constructor=e}function n(e,t){this.name=e||"Unknown",this.type=t||"Unknown"}function a(e,t){n.call(this,e,t||"Uint")}function i(e){return e.length%2==1?"0"+e:e}function r(e,t){n.call(this,e,t||"Float")}function o(e,t){n.call(this,e,t||"Container")}function p(e){o.call(this,"File","File"),this.setSource(e)}function y(e,t,n,a){if("object"==typeof n&&(a=n,n=void 0),!n)return new Promise((function(n){y(e,t,n,a)}));try{var i=new FileReader;i.onloadend=function(){try{var r=new p(new Uint8Array(i.result));r.fixDuration(t,a)&&(e=r.toBlob(e.type))}catch(e){}n(e)},i.readAsArrayBuffer(e)}catch(t){n(e)}}return n.prototype.updateBySource=function(){},n.prototype.setSource=function(e){this.source=e,this.updateBySource()},n.prototype.updateByData=function(){},n.prototype.setData=function(e){this.data=e,this.updateByData()},t(a,n),a.prototype.updateBySource=function(){this.data="";for(var e=0;e<this.source.length;e++){var t=this.source[e].toString(16);this.data+=i(t)}},a.prototype.updateByData=function(){var e=this.data.length/2;this.source=new Uint8Array(e);for(var t=0;t<e;t++){var n=this.data.substr(2*t,2);this.source[t]=parseInt(n,16)}},a.prototype.getValue=function(){return parseInt(this.data,16)},a.prototype.setValue=function(e){this.setData(i(e.toString(16)))},t(r,n),r.prototype.getFloatArrayType=function(){return this.source&&4===this.source.length?Float32Array:Float64Array},r.prototype.updateBySource=function(){var e=this.source.reverse(),t=new(this.getFloatArrayType())(e.buffer);this.data=t[0]},r.prototype.updateByData=function(){var e=new(this.getFloatArrayType())([this.data]),t=new Uint8Array(e.buffer);this.source=t.reverse()},r.prototype.getValue=function(){return this.data},r.prototype.setValue=function(e){this.setData(e)},t(o,n),o.prototype.readByte=function(){return this.source[this.offset++]},o.prototype.readUint=function(){for(var e=this.readByte(),t=8-e.toString(2).length,n=e-(1<<7-t),a=0;a<t;a++)n*=256,n+=this.readByte();return n},o.prototype.updateBySource=function(){for(this.data=[],this.offset=0;this.offset<this.source.length;this.offset=p){var t=this.readUint(),i=this.readUint(),p=Math.min(this.offset+i,this.source.length),y=this.source.slice(this.offset,p),m=e[t]||{name:"Unknown",type:"Unknown"},s=n;switch(m.type){case"Container":s=o;break;case"Uint":s=a;break;case"Float":s=r}var c=new s(m.name,m.type);c.setSource(y),this.data.push({id:t,idHex:t.toString(16),data:c})}},o.prototype.writeUint=function(e,t){for(var n=1,a=128;e>=a&&n<8;n++,a*=128);if(!t)for(var i=a+e,r=n-1;r>=0;r--){var o=i%256;this.source[this.offset+r]=o,i=(i-o)/256}this.offset+=n},o.prototype.writeSections=function(e){this.offset=0;for(var t=0;t<this.data.length;t++){var n=this.data[t],a=n.data.source,i=a.length;this.writeUint(n.id,e),this.writeUint(i,e),e||this.source.set(a,this.offset),this.offset+=i}return this.offset},o.prototype.updateByData=function(){var e=this.writeSections("draft");this.source=new Uint8Array(e),this.writeSections()},o.prototype.getSectionById=function(e){for(var t=0;t<this.data.length;t++){var n=this.data[t];if(n.id===e)return n.data}return null},t(p,o),p.prototype.fixDuration=function(e,t){var n=t&&t.logger;void 0===n?n=function(e){console.log(e)}:n||(n=function(){});var a=this.getSectionById(139690087);if(!a)return n("[fix-webm-duration] Segment section is missing"),!1;var i=a.getSectionById(88713574);if(!i)return n("[fix-webm-duration] Info section is missing"),!1;var o=i.getSectionById(710577);if(!o)return n("[fix-webm-duration] TimecodeScale section is missing"),!1;var p=i.getSectionById(1161);if(p){if(!(p.getValue()<=0))return n("[fix-webm-duration] Duration section is present"),!1;n("[fix-webm-duration] Duration section is present, but the value is empty. Applying "+e.toLocaleString()+" ms."),p.setValue(e)}else n("[fix-webm-duration] Duration section is missing. Applying "+e.toLocaleString()+" ms."),(p=new r("Duration","Float")).setValue(e),i.data.push({id:1161,data:p});return o.setValue(1e6),i.updateByData(),a.updateByData(),this.updateByData(),!0},p.prototype.toBlob=function(e){return new Blob([this.source.buffer],{type:e||"audio/webm"})},y.default=y,y}();';
  /*return '''
(function (name, definition) {
  window.jsFixWebmDuration = definition();
})('fix-webm-duration', function () {
  /*
   * This is the list of possible WEBM file sections by their IDs.
   * Possible types: Container, Binary, Uint, Int, String, Float, Date
   */
  var sections = {
      0xa45dfa3: { name: 'EBML', type: 'Container' },
      0x286: { name: 'EBMLVersion', type: 'Uint' },
      0x2f7: { name: 'EBMLReadVersion', type: 'Uint' },
      0x2f2: { name: 'EBMLMaxIDLength', type: 'Uint' },
      0x2f3: { name: 'EBMLMaxSizeLength', type: 'Uint' },
      0x282: { name: 'DocType', type: 'String' },
      0x287: { name: 'DocTypeVersion', type: 'Uint' },
      0x285: { name: 'DocTypeReadVersion', type: 'Uint' },
      0x6c: { name: 'Void', type: 'Binary' },
      0x3f: { name: 'CRC-32', type: 'Binary' },
      0xb538667: { name: 'SignatureSlot', type: 'Container' },
      0x3e8a: { name: 'SignatureAlgo', type: 'Uint' },
      0x3e9a: { name: 'SignatureHash', type: 'Uint' },
      0x3ea5: { name: 'SignaturePublicKey', type: 'Binary' },
      0x3eb5: { name: 'Signature', type: 'Binary' },
      0x3e5b: { name: 'SignatureElements', type: 'Container' },
      0x3e7b: { name: 'SignatureElementList', type: 'Container' },
      0x2532: { name: 'SignedElement', type: 'Binary' },
      0x8538067: { name: 'Segment', type: 'Container' },
      0x14d9b74: { name: 'SeekHead', type: 'Container' },
      0xdbb: { name: 'Seek', type: 'Container' },
      0x13ab: { name: 'SeekID', type: 'Binary' },
      0x13ac: { name: 'SeekPosition', type: 'Uint' },
      0x549a966: { name: 'Info', type: 'Container' },
      0x33a4: { name: 'SegmentUID', type: 'Binary' },
      0x3384: { name: 'SegmentFilename', type: 'String' },
      0x1cb923: { name: 'PrevUID', type: 'Binary' },
      0x1c83ab: { name: 'PrevFilename', type: 'String' },
      0x1eb923: { name: 'NextUID', type: 'Binary' },
      0x1e83bb: { name: 'NextFilename', type: 'String' },
      0x444: { name: 'SegmentFamily', type: 'Binary' },
      0x2924: { name: 'ChapterTranslate', type: 'Container' },
      0x29fc: { name: 'ChapterTranslateEditionUID', type: 'Uint' },
      0x29bf: { name: 'ChapterTranslateCodec', type: 'Uint' },
      0x29a5: { name: 'ChapterTranslateID', type: 'Binary' },
      0xad7b1: { name: 'TimecodeScale', type: 'Uint' },
      0x489: { name: 'Duration', type: 'Float' },
      0x461: { name: 'DateUTC', type: 'Date' },
      0x3ba9: { name: 'Title', type: 'String' },
      0xd80: { name: 'MuxingApp', type: 'String' },
      0x1741: { name: 'WritingApp', type: 'String' },
      // 0xf43b675: { name: 'Cluster', type: 'Container' },
      0x67: { name: 'Timecode', type: 'Uint' },
      0x1854: { name: 'SilentTracks', type: 'Container' },
      0x18d7: { name: 'SilentTrackNumber', type: 'Uint' },
      0x27: { name: 'Position', type: 'Uint' },
      0x2b: { name: 'PrevSize', type: 'Uint' },
      0x23: { name: 'SimpleBlock', type: 'Binary' },
      0x20: { name: 'BlockGroup', type: 'Container' },
      0x21: { name: 'Block', type: 'Binary' },
      0x22: { name: 'BlockVirtual', type: 'Binary' },
      0x35a1: { name: 'BlockAdditions', type: 'Container' },
      0x26: { name: 'BlockMore', type: 'Container' },
      0x6e: { name: 'BlockAddID', type: 'Uint' },
      0x25: { name: 'BlockAdditional', type: 'Binary' },
      0x1b: { name: 'BlockDuration', type: 'Uint' },
      0x7a: { name: 'ReferencePriority', type: 'Uint' },
      0x7b: { name: 'ReferenceBlock', type: 'Int' },
      0x7d: { name: 'ReferenceVirtual', type: 'Int' },
      0x24: { name: 'CodecState', type: 'Binary' },
      0x35a2: { name: 'DiscardPadding', type: 'Int' },
      0xe: { name: 'Slices', type: 'Container' },
      0x68: { name: 'TimeSlice', type: 'Container' },
      0x4c: { name: 'LaceNumber', type: 'Uint' },
      0x4d: { name: 'FrameNumber', type: 'Uint' },
      0x4b: { name: 'BlockAdditionID', type: 'Uint' },
      0x4e: { name: 'Delay', type: 'Uint' },
      0x4f: { name: 'SliceDuration', type: 'Uint' },
      0x48: { name: 'ReferenceFrame', type: 'Container' },
      0x49: { name: 'ReferenceOffset', type: 'Uint' },
      0x4a: { name: 'ReferenceTimeCode', type: 'Uint' },
      0x2f: { name: 'EncryptedBlock', type: 'Binary' },
      0x654ae6b: { name: 'Tracks', type: 'Container' },
      0x2e: { name: 'TrackEntry', type: 'Container' },
      0x57: { name: 'TrackNumber', type: 'Uint' },
      0x33c5: { name: 'TrackUID', type: 'Uint' },
      0x3: { name: 'TrackType', type: 'Uint' },
      0x39: { name: 'FlagEnabled', type: 'Uint' },
      0x8: { name: 'FlagDefault', type: 'Uint' },
      0x15aa: { name: 'FlagForced', type: 'Uint' },
      0x1c: { name: 'FlagLacing', type: 'Uint' },
      0x2de7: { name: 'MinCache', type: 'Uint' },
      0x2df8: { name: 'MaxCache', type: 'Uint' },
      0x3e383: { name: 'DefaultDuration', type: 'Uint' },
      0x34e7a: { name: 'DefaultDecodedFieldDuration', type: 'Uint' },
      0x3314f: { name: 'TrackTimecodeScale', type: 'Float' },
      0x137f: { name: 'TrackOffset', type: 'Int' },
      0x15ee: { name: 'MaxBlockAdditionID', type: 'Uint' },
      0x136e: { name: 'Name', type: 'String' },
      0x2b59c: { name: 'Language', type: 'String' },
      0x6: { name: 'CodecID', type: 'String' },
      0x23a2: { name: 'CodecPrivate', type: 'Binary' },
      0x58688: { name: 'CodecName', type: 'String' },
      0x3446: { name: 'AttachmentLink', type: 'Uint' },
      0x1a9697: { name: 'CodecSettings', type: 'String' },
      0x1b4040: { name: 'CodecInfoURL', type: 'String' },
      0x6b240: { name: 'CodecDownloadURL', type: 'String' },
      0x2a: { name: 'CodecDecodeAll', type: 'Uint' },
      0x2fab: { name: 'TrackOverlay', type: 'Uint' },
      0x16aa: { name: 'CodecDelay', type: 'Uint' },
      0x16bb: { name: 'SeekPreRoll', type: 'Uint' },
      0x2624: { name: 'TrackTranslate', type: 'Container' },
      0x26fc: { name: 'TrackTranslateEditionUID', type: 'Uint' },
      0x26bf: { name: 'TrackTranslateCodec', type: 'Uint' },
      0x26a5: { name: 'TrackTranslateTrackID', type: 'Binary' },
      0x60: { name: 'Video', type: 'Container' },
      0x1a: { name: 'FlagInterlaced', type: 'Uint' },
      0x13b8: { name: 'StereoMode', type: 'Uint' },
      0x13c0: { name: 'AlphaMode', type: 'Uint' },
      0x13b9: { name: 'OldStereoMode', type: 'Uint' },
      0x30: { name: 'PixelWidth', type: 'Uint' },
      0x3a: { name: 'PixelHeight', type: 'Uint' },
      0x14aa: { name: 'PixelCropBottom', type: 'Uint' },
      0x14bb: { name: 'PixelCropTop', type: 'Uint' },
      0x14cc: { name: 'PixelCropLeft', type: 'Uint' },
      0x14dd: { name: 'PixelCropRight', type: 'Uint' },
      0x14b0: { name: 'DisplayWidth', type: 'Uint' },
      0x14ba: { name: 'DisplayHeight', type: 'Uint' },
      0x14b2: { name: 'DisplayUnit', type: 'Uint' },
      0x14b3: { name: 'AspectRatioType', type: 'Uint' },
      0xeb524: { name: 'ColourSpace', type: 'Binary' },
      0xfb523: { name: 'GammaValue', type: 'Float' },
      0x383e3: { name: 'FrameRate', type: 'Float' },
      0x61: { name: 'Audio', type: 'Container' },
      0x35: { name: 'SamplingFrequency', type: 'Float' },
      0x38b5: { name: 'OutputSamplingFrequency', type: 'Float' },
      0x1f: { name: 'Channels', type: 'Uint' },
      0x3d7b: { name: 'ChannelPositions', type: 'Binary' },
      0x2264: { name: 'BitDepth', type: 'Uint' },
      0x62: { name: 'TrackOperation', type: 'Container' },
      0x63: { name: 'TrackCombinePlanes', type: 'Container' },
      0x64: { name: 'TrackPlane', type: 'Container' },
      0x65: { name: 'TrackPlaneUID', type: 'Uint' },
      0x66: { name: 'TrackPlaneType', type: 'Uint' },
      0x69: { name: 'TrackJoinBlocks', type: 'Container' },
      0x6d: { name: 'TrackJoinUID', type: 'Uint' },
      0x40: { name: 'TrickTrackUID', type: 'Uint' },
      0x41: { name: 'TrickTrackSegmentUID', type: 'Binary' },
      0x46: { name: 'TrickTrackFlag', type: 'Uint' },
      0x47: { name: 'TrickMasterTrackUID', type: 'Uint' },
      0x44: { name: 'TrickMasterTrackSegmentUID', type: 'Binary' },
      0x2d80: { name: 'ContentEncodings', type: 'Container' },
      0x2240: { name: 'ContentEncoding', type: 'Container' },
      0x1031: { name: 'ContentEncodingOrder', type: 'Uint' },
      0x1032: { name: 'ContentEncodingScope', type: 'Uint' },
      0x1033: { name: 'ContentEncodingType', type: 'Uint' },
      0x1034: { name: 'ContentCompression', type: 'Container' },
      0x254: { name: 'ContentCompAlgo', type: 'Uint' },
      0x255: { name: 'ContentCompSettings', type: 'Binary' },
      0x1035: { name: 'ContentEncryption', type: 'Container' },
      0x7e1: { name: 'ContentEncAlgo', type: 'Uint' },
      0x7e2: { name: 'ContentEncKeyID', type: 'Binary' },
      0x7e3: { name: 'ContentSignature', type: 'Binary' },
      0x7e4: { name: 'ContentSigKeyID', type: 'Binary' },
      0x7e5: { name: 'ContentSigAlgo', type: 'Uint' },
      0x7e6: { name: 'ContentSigHashAlgo', type: 'Uint' },
      0xc53bb6b: { name: 'Cues', type: 'Container' },
      0x3b: { name: 'CuePoint', type: 'Container' },
      0x33: { name: 'CueTime', type: 'Uint' },
      0x37: { name: 'CueTrackPositions', type: 'Container' },
      0x77: { name: 'CueTrack', type: 'Uint' },
      0x71: { name: 'CueClusterPosition', type: 'Uint' },
      0x70: { name: 'CueRelativePosition', type: 'Uint' },
      0x32: { name: 'CueDuration', type: 'Uint' },
      0x1378: { name: 'CueBlockNumber', type: 'Uint' },
      0x6a: { name: 'CueCodecState', type: 'Uint' },
      0x5b: { name: 'CueReference', type: 'Container' },
      0x16: { name: 'CueRefTime', type: 'Uint' },
      0x17: { name: 'CueRefCluster', type: 'Uint' },
      0x135f: { name: 'CueRefNumber', type: 'Uint' },
      0x6b: { name: 'CueRefCodecState', type: 'Uint' },
      0x941a469: { name: 'Attachments', type: 'Container' },
      0x21a7: { name: 'AttachedFile', type: 'Container' },
      0x67e: { name: 'FileDescription', type: 'String' },
      0x66e: { name: 'FileName', type: 'String' },
      0x660: { name: 'FileMimeType', type: 'String' },
      0x65c: { name: 'FileData', type: 'Binary' },
      0x6ae: { name: 'FileUID', type: 'Uint' },
      0x675: { name: 'FileReferral', type: 'Binary' },
      0x661: { name: 'FileUsedStartTime', type: 'Uint' },
      0x662: { name: 'FileUsedEndTime', type: 'Uint' },
      0x43a770: { name: 'Chapters', type: 'Container' },
      0x5b9: { name: 'EditionEntry', type: 'Container' },
      0x5bc: { name: 'EditionUID', type: 'Uint' },
      0x5bd: { name: 'EditionFlagHidden', type: 'Uint' },
      0x5db: { name: 'EditionFlagDefault', type: 'Uint' },
      0x5dd: { name: 'EditionFlagOrdered', type: 'Uint' },
      0x36: { name: 'ChapterAtom', type: 'Container' },
      0x33c4: { name: 'ChapterUID', type: 'Uint' },
      0x1654: { name: 'ChapterStringUID', type: 'String' },
      0x11: { name: 'ChapterTimeStart', type: 'Uint' },
      0x12: { name: 'ChapterTimeEnd', type: 'Uint' },
      0x18: { name: 'ChapterFlagHidden', type: 'Uint' },
      0x598: { name: 'ChapterFlagEnabled', type: 'Uint' },
      0x2e67: { name: 'ChapterSegmentUID', type: 'Binary' },
      0x2ebc: { name: 'ChapterSegmentEditionUID', type: 'Uint' },
      0x23c3: { name: 'ChapterPhysicalEquiv', type: 'Uint' },
      0xf: { name: 'ChapterTrack', type: 'Container' },
      0x9: { name: 'ChapterTrackNumber', type: 'Uint' },
      0x0: { name: 'ChapterDisplay', type: 'Container' },
      0x5: { name: 'ChapString', type: 'String' },
      0x37c: { name: 'ChapLanguage', type: 'String' },
      0x37e: { name: 'ChapCountry', type: 'String' },
      0x2944: { name: 'ChapProcess', type: 'Container' },
      0x2955: { name: 'ChapProcessCodecID', type: 'Uint' },
      0x50d: { name: 'ChapProcessPrivate', type: 'Binary' },
      0x2911: { name: 'ChapProcessCommand', type: 'Container' },
      0x2922: { name: 'ChapProcessTime', type: 'Uint' },
      0x2933: { name: 'ChapProcessData', type: 'Binary' },
      0x254c367: { name: 'Tags', type: 'Container' },
      0x3373: { name: 'Tag', type: 'Container' },
      0x23c0: { name: 'Targets', type: 'Container' },
      0x28ca: { name: 'TargetTypeValue', type: 'Uint' },
      0x23ca: { name: 'TargetType', type: 'String' },
      0x23c5: { name: 'TagTrackUID', type: 'Uint' },
      0x23c9: { name: 'TagEditionUID', type: 'Uint' },
      0x23c4: { name: 'TagChapterUID', type: 'Uint' },
      0x23c6: { name: 'TagAttachmentUID', type: 'Uint' },
      0x27c8: { name: 'SimpleTag', type: 'Container' },
      0x5a3: { name: 'TagName', type: 'String' },
      0x47a: { name: 'TagLanguage', type: 'String' },
      0x484: { name: 'TagDefault', type: 'Uint' },
      0x487: { name: 'TagString', type: 'String' },
      0x485: { name: 'TagBinary', type: 'Binary' }
  };

  function doInherit(newClass, baseClass) {
      newClass.prototype = Object.create(baseClass.prototype);
      newClass.prototype.constructor = newClass;
  }

  function WebmBase(name, type) {
      this.name = name || 'Unknown';
      this.type = type || 'Unknown';
  }
  WebmBase.prototype.updateBySource = function() { };
  WebmBase.prototype.setSource = function(source) {
      this.source = source;
      this.updateBySource();
  };
  WebmBase.prototype.updateByData = function() { };
  WebmBase.prototype.setData = function(data) {
      this.data = data;
      this.updateByData();
  };

  function WebmUint(name, type) {
      WebmBase.call(this, name, type || 'Uint');
  }
  doInherit(WebmUint, WebmBase);
  function padHex(hex) {
      return hex.length % 2 === 1 ? '0' + hex : hex;
  }
  WebmUint.prototype.updateBySource = function() {
      // use hex representation of a number instead of number value
      this.data = '';
      for (var i = 0; i < this.source.length; i++) {
          var hex = this.source[i].toString(16);
          this.data += padHex(hex);
      }
  };
  WebmUint.prototype.updateByData = function() {
      var length = this.data.length / 2;
      this.source = new Uint8Array(length);
      for (var i = 0; i < length; i++) {
          var hex = this.data.substr(i * 2, 2);
          this.source[i] = parseInt(hex, 16);
      }
  };
  WebmUint.prototype.getValue = function() {
      return parseInt(this.data, 16);
  };
  WebmUint.prototype.setValue = function(value) {
      this.setData(padHex(value.toString(16)));
  };

  function WebmFloat(name, type) {
      WebmBase.call(this, name, type || 'Float');
  }
  doInherit(WebmFloat, WebmBase);
  WebmFloat.prototype.getFloatArrayType = function() {
      return this.source && this.source.length === 4 ? Float32Array : Float64Array;
  };
  WebmFloat.prototype.updateBySource = function() {
      var byteArray = this.source.reverse();
      var floatArrayType = this.getFloatArrayType();
      var floatArray = new floatArrayType(byteArray.buffer);
      this.data = floatArray[0];
  };
  WebmFloat.prototype.updateByData = function() {
      var floatArrayType = this.getFloatArrayType();
      var floatArray = new floatArrayType([ this.data ]);
      var byteArray = new Uint8Array(floatArray.buffer);
      this.source = byteArray.reverse();
  };
  WebmFloat.prototype.getValue = function() {
      return this.data;
  };
  WebmFloat.prototype.setValue = function(value) {
      this.setData(value);
  };

  function WebmContainer(name, type) {
      WebmBase.call(this, name, type || 'Container');
  }
  doInherit(WebmContainer, WebmBase);
  WebmContainer.prototype.readByte = function() {
      return this.source[this.offset++];
  };
  WebmContainer.prototype.readUint = function() {
      var firstByte = this.readByte();
      var bytes = 8 - firstByte.toString(2).length;
      var value = firstByte - (1 << (7 - bytes));
      for (var i = 0; i < bytes; i++) {
          // don't use bit operators to support x86
          value *= 256;
          value += this.readByte();
      }
      return value;
  };
  WebmContainer.prototype.updateBySource = function() {
      this.data = [];
      for (this.offset = 0; this.offset < this.source.length; this.offset = end) {
          var id = this.readUint();
          var len = this.readUint();
          var end = Math.min(this.offset + len, this.source.length);
          var data = this.source.slice(this.offset, end);

          var info = sections[id] || { name: 'Unknown', type: 'Unknown' };
          var ctr = WebmBase;
          switch (info.type) {
              case 'Container':
                  ctr = WebmContainer;
                  break;
              case 'Uint':
                  ctr = WebmUint;
                  break;
              case 'Float':
                  ctr = WebmFloat;
                  break;
          }
          var section = new ctr(info.name, info.type);
          section.setSource(data);
          this.data.push({
              id: id,
              idHex: id.toString(16),
              data: section
          });
      }
  };
  WebmContainer.prototype.writeUint = function(x, draft) {
      for (var bytes = 1, flag = 0x80; x >= flag && bytes < 8; bytes++, flag *= 0x80) { }

      if (!draft) {
          var value = flag + x;
          for (var i = bytes - 1; i >= 0; i--) {
              // don't use bit operators to support x86
              var c = value % 256;
              this.source[this.offset + i] = c;
              value = (value - c) / 256;
          }
      }

      this.offset += bytes;
  };
  WebmContainer.prototype.writeSections = function(draft) {
      this.offset = 0;
      for (var i = 0; i < this.data.length; i++) {
          var section = this.data[i],
              content = section.data.source,
              contentLength = content.length;
          this.writeUint(section.id, draft);
          this.writeUint(contentLength, draft);
          if (!draft) {
              this.source.set(content, this.offset);
          }
          this.offset += contentLength;
      }
      return this.offset;
  };
  WebmContainer.prototype.updateByData = function() {
      // run without accessing this.source to determine total length - need to know it to create Uint8Array
      var length = this.writeSections('draft');
      this.source = new Uint8Array(length);
      // now really write data
      this.writeSections();
  };
  WebmContainer.prototype.getSectionById = function(id) {
      for (var i = 0; i < this.data.length; i++) {
          var section = this.data[i];
          if (section.id === id) {
              return section.data;
          }
      }
      return null;
  };

  function WebmFile(source) {
      WebmContainer.call(this, 'File', 'File');
      this.setSource(source);
  }
  doInherit(WebmFile, WebmContainer);
  WebmFile.prototype.fixDuration = function(duration, options) {
      var logger = options && options.logger;
      if (logger === undefined) {
          logger = function(message) {
              console.log(message);
          };
      } else if (!logger) {
          logger = function() { };
      }

      var segmentSection = this.getSectionById(0x8538067);
      if (!segmentSection) {
          logger('[fix-webm-duration] Segment section is missing');
          return false;
      }

      var infoSection = segmentSection.getSectionById(0x549a966);
      if (!infoSection) {
          logger('[fix-webm-duration] Info section is missing');
          return false;
      }

      var timeScaleSection = infoSection.getSectionById(0xad7b1);
      if (!timeScaleSection) {
          logger('[fix-webm-duration] TimecodeScale section is missing');
          return false;
      }

      var durationSection = infoSection.getSectionById(0x489);
      if (durationSection) {
          if (durationSection.getValue() <= 0) {
              logger('[fix-webm-duration] Duration section is present, but the value is empty. Applying ' + duration.toLocaleString() + ' ms.');
              durationSection.setValue(duration);
          } else {
              logger('[fix-webm-duration] Duration section is present');
              return false;
          }
      } else {
          logger('[fix-webm-duration] Duration section is missing. Applying ' + duration.toLocaleString() + ' ms.');
          // append Duration section
          durationSection = new WebmFloat('Duration', 'Float');
          durationSection.setValue(duration);
          infoSection.data.push({
              id: 0x489,
              data: durationSection
          });
      }

      // set default time scale to 1 millisecond (1000000 nanoseconds)
      timeScaleSection.setValue(1000000);
      infoSection.updateByData();
      segmentSection.updateByData();
      this.updateByData();

      return true;
  };
  WebmFile.prototype.toBlob = function(mimeType) {
      return new Blob([ this.source.buffer ], { type: mimeType || 'audio/webm' });
  };

  function fixWebmDuration(blob, duration, callback, options) {
      // The callback may be omitted - then the third argument is options
      if (typeof callback === "object") {
          options = callback;
          callback = undefined;
      }

      if (!callback) {
          return new Promise(function(resolve) {
              fixWebmDuration(blob, duration, resolve, options);
          });
      }

      try {
          var reader = new FileReader();
          reader.onloadend = function() {
              try {
                  var file = new WebmFile(new Uint8Array(reader.result));
                  if (file.fixDuration(duration, options)) {
                      blob = file.toBlob(blob.type);
                  }
              } catch (ex) {
                  // ignore
              }
              callback(blob);
          };
          reader.readAsArrayBuffer(blob);
      } catch (ex) {
          callback(blob);
      }
  }

  // Support AMD import default
  fixWebmDuration.default = fixWebmDuration;

  return fixWebmDuration;
});
''';*/
}
