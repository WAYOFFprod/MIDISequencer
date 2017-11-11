//
//  MIDISequencer.swift
//  MIDISequencer
//
//  Created by Cem Olcay on 12/09/2017.
//
//

import Foundation
import AudioKit
import MusicTheorySwift

/// Sequencer with multiple tracks and multiple channels to broadcast MIDI sequences other apps.
public class MIDISequencer {
  /// Name of the sequencer.
  public private(set) var midiOutputName: String
  /// Sequencer that sequences the `MIDISequencerStep`s in each `MIDISequencerTrack`.
  public private(set) var sequencer: AKSequencer?
  /// Global MIDI referance object.
  public let midi = AKMIDI()
  /// MIDI callback instrument that sends MIDI events to other apps.
  public private(set) var midiCallbackInstrument: MIDISequencerCallbackInstrument

  /// All tracks in sequencer.
  public var tracks = [MIDISequencerTrack]()
  /// Tempo (BPM) and time signature value of sequencer.
  public var tempo = Tempo(timeSignature: TimeSignature(beats: 4, noteValue: .quarter), bpm: 120) { didSet{ sequencer?.setTempo(tempo.bpm) }}

  /// Initilizes the sequencer with its name.
  ///
  /// - Parameter midiOutputName: Name of sequencer that seen by other apps.
  public init(midiOutputName: String) {
    self.midiOutputName = midiOutputName
    midiCallbackInstrument = MIDISequencerCallbackInstrument(midi: midi)
    midi.createVirtualOutputPort(name: midiOutputName)
  }

  deinit {
    stop()
  }

  /// Creates an `AKSequencer` from `tracks`
  private func setupSequencer() {
    sequencer = AKSequencer()

    for track in tracks {
      guard let newTrack = sequencer?.newTrack(track.name) else { continue }
      newTrack.setMIDIOutput(midiCallbackInstrument.midiIn)

      for step in track.steps {
        for note in step.notes {
          for channel in track.midiChannels {
            newTrack.add(
              noteNumber: MIDINoteNumber(note.midiNote),
              velocity: MIDIVelocity(step.velocity.velocity),
              position: AKDuration(beats: step.position),
              duration: AKDuration(beats: step.duration),
              channel: MIDIChannel(channel))
          }
        }
      }
    }

    sequencer?.setTempo(tempo.bpm)
    sequencer?.enableLooping(AKDuration(beats: tracks.map({ $0.duration }).sorted().last ?? 0))
  }

  /// Adds a track to its `tracks`.
  ///
  /// - Parameter track: Track will be added.
  public func addTrack(track: MIDISequencerTrack) {
    tracks.append(track)
  }

  /// Removes a track from its `tracks` at index.
  ///
  /// - Parameter index: Index of track that will be removed.
  public func removeTrack(at index: Int) {
    tracks.remove(at: index)
  }

  /// Mutes track.
  ///
  /// - Parameter track: Track going to be muted.
  func muteTrack(track: MIDISequencerTrack) {
    guard let index = tracks.index(where: { $0 == track }) else { return }
    tracks[index].isMute = true
    tracks[index].isSolo = false
    setupSequencer()
  }

  /// Unmutes track.
  ///
  /// - Parameter track: Track going to be unmuted.
  func unmuteTrack(track: MIDISequencerTrack) {
    guard let index = tracks.index(where: { $0 == track }) else { return }
    tracks[index].isMute = false
    setupSequencer()
  }

  /// Makes track solo.
  ///
  /// - Parameter track: Track going to be solo.
  func soloTrack(track: MIDISequencerTrack) {
    for t in tracks {
      if t == track {
        t.isMute = false
        t.isSolo = true
      } else {
        t.isMute = true
      }
    }
    setupSequencer()
  }

  /// Disables track solo.
  ///
  /// - Parameter track: Track going to be unsolo.
  func unsoloTrack(track: MIDISequencerTrack) {
    if tracks.filter({ $0.isSolo }).count > 1 {
      guard let index = tracks.index(where: { $0 == track }) else { return }
      tracks[index].isSolo = false
    } else {
      for t in tracks {
        t.isSolo = false
      }
    }
    setupSequencer()
  }

  /// Plays the sequence from begining.
  public func play() {
    setupSequencer()
    sequencer?.play()
  }

  /// Setups sequencer on background thread and starts playing it.
  ///
  /// - Parameter completion: Fires when setup complete. Useful to dismiss any loading state.
  public func playAsync(completion: (() -> Void)? = nil) {
    DispatchQueue.main.async {
      self.play()
      completion?()
    }
  }

  /// Stops playing the sequence.
  public func stop() {
    sequencer?.stop()
    sequencer = nil
  }
}
