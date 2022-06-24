import 'dart:developer';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/src/record.dart';

void main() async {

  Record? record;

  setUp((){
    record = Record();
  });


  test('Get capture devices, compatible with [ Windows, Linux ]', () async {
    List<Device> captureDevices = await record!.getCaptureDevices(); // for default is Empty [];
    await expectLater(captureDevices, isNotEmpty, reason: 'No capture devices found.');
    for( Device capture in captureDevices ){
      log(capture.name!);
    }
  });


  test('Get playback devices, compatible with [ Windows, Linux ]', () async {
    List<Device> captureDevices = await record!.getPlaybackDevices(); // for default is Empty [];
    await expectLater(captureDevices, isNotEmpty, reason: 'No playback devices found.');
    for( Device capture in captureDevices ){
      log(capture.name!);
    }
  });


  test('Recording using an input device.', () async {
    int positionDevice = 0; // Change this to choose the device from the for list.
    Device? device;
    List<Device> captureDevices = await record!.getCaptureDevices();

    for( int i=0; i<captureDevices.length; i++ ){
      debugPrint(captureDevices[i].toMap().toString());
      if( i == positionDevice ){
        device = captureDevices[i];
      }
    }

    expect(device, isNotNull, reason: 'No device found.');
    log('capture device selected: ${device?.name}');
    
    log('Creating directory for your test recording.');
    Directory newDir = Directory('records');
    Directory recordDir = await newDir.create();
    expect(await recordDir.exists(), true, reason: 'The folder could not be created.');

    log('Next, a 5-second recording will be made with the selected capture device.');
    await record!.start(
      path: 'D:\\Trabajos\\record\\record\\records\\rec.m4a', // Change this to an absolute path to the test records folder.
      captureDevice: device
    );
    
    await Future.delayed(const Duration(seconds: 5), () async 
    => await record!.stop());

    log('✓ Finished recording: records/rec.m4a');
  });  
}