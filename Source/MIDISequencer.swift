//
//  MIDISequencer.swift
//  MIDISequencer
//
//  Created by Cem Olcay on 12/09/2017.
//
//

import Foundation
import AudioKit
import CoreMIDI

/// Sequencer's duration type.
public enum MIDISequencerDuration {
  /// Longest track's duration is the duration.
  case auto
  /// Number of bars in beat form.
  case bars(Double)
  /// Number of steps in beat form.
  case steps(Double)

  /// Calulates the duration of the sequencer.
  public func duration(of sequencer: MIDISequencer) -> Double {
    switch self {
    case .auto:
      return sequencer.tracks.map({ $0.duration }).sorted().last ?? 0
    case .bars(let barCount):
      return barCount * 4.0 // A bar has 4 steps.
    case .steps(let stepCount):
      return stepCount
    }
  }
}

/// Sequencer with up to 16 tracks and multiple channels to broadcast MIDI sequences other apps.
public class MIDISequencer: MIDIListener {
    
    /// Name of the sequencer.
    public private(set) var name: String
    /// Sequencer that sequences the `MIDISequencerStep`s in each `MIDISequencerTrack`.
    public private(set) var sequencer: AppleSequencer?
    /// Global MIDI referance object.
    public let midi = MIDI()
    /// All tracks in sequencer.
    public var tracks = [MIDISequencerTrack]()
    /// Tempo (BPM) and time signature value of sequencer.
    public var tempo: Double = 120.0
    /// Duration of the sequencer. Defaults auto.
    public var duration: MIDISequencerDuration = .auto

    /// Returns true if sequencer is playing.
    public var isPlaying: Bool {
      return sequencer?.isPlaying ?? false
    }

    // MARK: Init

    /// Initilizes the sequencer with its name.
    ///
    /// - Parameter name: Name of sequencer that seen by other apps.
    public init(name: String) {
        self.name = name
        midi.createVirtualInputPorts(names: ["\(name) In"])
        midi.createVirtualOutputPorts(names: ["\(name) Out"])
        midi.addListener(self)
    }

    deinit {
        midi.destroyAllVirtualPorts()
        stop()
    }

    /// Creates an `AKSequencer` from `tracks`
    public func setupSequencer() {
      sequencer = AppleSequencer()
      
      for (index, track) in tracks.enumerated() {
        guard let newTrack = sequencer?.newTrack(track.name) else { continue }
          newTrack.setMIDIOutput(midi.virtualInputs[0])

          for step in track.steps {
            let velocity = MIDIVelocity(step.velocity.velocity)
            let position = Duration(beats: step.position)
            let duration = Duration(beats: step.duration)

            for note in step.notes {
              let noteNumber = MIDINoteNumber(note.rawValue)

              newTrack.add(
                noteNumber: noteNumber,
                velocity: velocity,
                position: position,
                duration: duration,
                channel: MIDIChannel(index))
          }
        }
      }

      sequencer?.setTempo(tempo)
      sequencer?.setLength(Duration(beats: duration.duration(of: self)))
      sequencer?.enableLooping()
    }

    // MARK: Sequencing

    /// Plays the sequence from begining if any MIDI Output including virtual one setted up.
    public func play() {
      setupSequencer()
      sequencer?.play()
    }

    /// Setups sequencer on background thread and starts playing it.
    ///
    /// - Parameter completion: Fires when setup complete.
    public func playAsync(completion: (() -> Void)? = nil) {
      DispatchQueue.global(qos: .background).async {
        self.setupSequencer()
        DispatchQueue.main.async {
          self.sequencer?.play()
          completion?()
        }
      }
    }

    /// Stops playing the sequence.
    public func stop() {
      sequencer?.stop()
      sequencer = nil
    }

    // MARK: Track Management

    /// Adds a track to optional index.
    ///
    /// - Parameters:
    ///   - track: Adding track.
    ///   - index: Optional index of adding track. Appends end of array if not defined. Defaults nil.
    public func add(track: MIDISequencerTrack) {
      if tracks.count < 16 {
        tracks.append(track)
      }
    }

    /// Removes a track.
    ///
    /// - Parameter track: Track going to be removed.
    /// - Returns: Returns result of removing operation in discardableResult form.
    @discardableResult public func remove(track: MIDISequencerTrack) -> Bool {
      guard let index = tracks.firstIndex(of: track) else { return false }
      tracks.remove(at: index)
      return true
    }

    /// Sets mute state of track to true.
    ///
    /// - Parameter on: Set mute or not.
    /// - Parameter track: Track going to be mute.
    /// - Returns: If track is not this sequenecer's, return false, else return true.
    @discardableResult public func mute(on: Bool, track: MIDISequencerTrack) -> Bool {
      guard let index = tracks.firstIndex(of: track) else { return false }
      tracks[index].isMute = on
      return true
    }

    /// Sets solo state of track to true.
    ///
    /// - Parameter on: Set solo or not.
    /// - Parameter track: Track going to be enable soloing.
    /// - Returns: If track is not this sequenecer's, return false, else return true.
    @discardableResult public func solo(on: Bool, track: MIDISequencerTrack) -> Bool {
      guard let index = tracks.firstIndex(of: track) else { return false }
      tracks[index].isSolo = on
      return true
    }

    // MARK: MIDIListener
    
    public func receivedMIDINoteOn(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        receivedMIDINoteOn(noteNumber: noteNumber, velocity: velocity, channel: channel)
    }
    public func receivedMIDINoteOn(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
      guard sequencer?.isPlaying == true, tracks.indices.contains(Int(channel)) else {
        midi.sendNoteOffMessage(noteNumber: noteNumber, velocity: velocity)
        return
      }

      let track = tracks[Int(channel)]
      for trackChannel in track.midiChannels {
        midi.sendNoteOnMessage(
          noteNumber: noteNumber,
          velocity: track.isMute ? 0 : velocity,
          channel: MIDIChannel(trackChannel))
      }
    }
    
    public func receivedMIDINoteOff(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        receivedMIDINoteOn(noteNumber: noteNumber, velocity: velocity, channel: channel)
    }

    public func receivedMIDINoteOff(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
      guard sequencer?.isPlaying == true,
        tracks.indices.contains(Int(channel))
        else { return }

      let track = tracks[Int(channel)]
      for trackChannel in track.midiChannels {
        midi.sendNoteOffMessage(
          noteNumber: noteNumber,
          velocity: velocity,
          channel: MIDIChannel(trackChannel))
      }
    }
    
    public func receivedMIDIController(_ controller: MIDIByte, value: MIDIByte, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDIAftertouch(noteNumber: MIDINoteNumber, pressure: MIDIByte, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDIAftertouch(_ pressure: MIDIByte, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDIPitchWheel(_ pitchWheelValue: MIDIWord, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDIProgramChange(_ program: MIDIByte, channel: MIDIChannel, portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDISystemCommand(_ data: [MIDIByte], portID: MIDIUniqueID?, timeStamp: MIDITimeStamp?) {
        
    }
    
    public func receivedMIDISetupChange() {
        
    }
    
    public func receivedMIDIPropertyChange(propertyChangeInfo: MIDIObjectPropertyChangeNotification) {
        
    }
    
    public func receivedMIDINotification(notification: MIDINotification) {
        
    }
    
  
}
