import BlithCore
import Foundation

/// Plain descriptions of what the main muscles do, for the selected-muscle card. General anatomy
/// for orientation, never a statement about the person's own body.
enum MuscleGuide {
    struct Entry {
        /// Where it sits, e.g. "Chest" or "Back of thigh".
        let group: String
        /// What it mainly does, one plain sentence fragment.
        let action: String
    }

    static func entry(for muscle: Body3DModel.Muscle) -> Entry? {
        if let entry = table[baseName(muscle.name)] { return entry }
        switch muscle.bodyRegion {
        case .rightHand?, .leftHand?, .rightWrist?, .leftWrist?:
            return Entry(group: "Hand", action: "Fine finger and thumb movements, and grip")
        case .rightFoot?, .leftFoot?, .rightAnkle?, .leftAnkle?:
            return Entry(group: "Foot", action: "Moving the toes and supporting the arch")
        default:
            return nil
        }
    }

    /// "Gastrocnemius (medial head)" → "Gastrocnemius".
    static func baseName(_ name: String) -> String {
        guard let open = name.firstIndex(of: "(") else { return name }
        return name[..<open].trimmingCharacters(in: .whitespaces)
    }

    /// "Left side" / "Right side"; nil for midline muscles.
    static func sideLabel(_ muscle: Body3DModel.Muscle) -> String? {
        switch muscle.side {
        case "left": "Left side"
        case "right": "Right side"
        default: nil
        }
    }

    private static let forearmFlexor = Entry(group: "Forearm", action: "Bending the wrist and fingers, and gripping")
    private static let forearmExtensor = Entry(group: "Forearm", action: "Lifting the wrist and straightening the fingers")
    private static let thumbExtensor = Entry(group: "Forearm", action: "Moving the thumb out and back")
    private static let quadriceps = Entry(group: "Front of thigh", action: "Straightening the knee")
    private static let hamstring = Entry(group: "Back of thigh", action: "Bending the knee and extending the hip")
    private static let adductor = Entry(group: "Inner thigh", action: "Drawing the legs together and steadying the hip")
    private static let fibularis = Entry(group: "Outer shin", action: "Turning the sole outward and steadying the ankle")
    private static let backExtensor = Entry(group: "Lower back", action: "Straightening and steadying the spine")
    private static let rotatorCuff = Entry(group: "Shoulder", action: "Turning the arm outward and holding the shoulder joint steady")

    private static let table: [String: Entry] = [
        "Pectoralis major": Entry(group: "Chest", action: "Pushing, and bringing the arm forward and across the body"),
        "Serratus anterior": Entry(group: "Side of chest", action: "Moving the shoulder blade forward, as in a punch or push"),
        "Deltoid": Entry(group: "Shoulder", action: "Lifting the arm forward, out to the side and back"),
        "Infraspinatus": rotatorCuff,
        "Teres minor": rotatorCuff,
        "Teres major": Entry(group: "Shoulder", action: "Pulling the arm down and in toward the body"),
        "Trapezius": Entry(group: "Upper back and neck", action: "Shrugging, drawing the shoulder blades back and steadying the neck"),
        "Latissimus dorsi": Entry(group: "Back", action: "Pulling the arm down and back, as in a pull-up or rowing"),
        "Levator scapulae": Entry(group: "Neck", action: "Lifting the shoulder blade"),
        "Iliocostalis lumborum": backExtensor,
        "Longissimus thoracis": backExtensor,
        "Sternocleidomastoid": Entry(group: "Neck", action: "Turning the head and bending the neck forward"),
        "Splenius capitis": Entry(group: "Neck", action: "Tilting the head back and turning it"),
        "Scalenus medius": Entry(group: "Neck", action: "Bending the neck to the side and helping with deep breaths"),
        "Platysma": Entry(group: "Neck", action: "Tensing the skin of the neck and drawing the mouth down"),
        "Biceps brachii": Entry(group: "Upper arm", action: "Bending the elbow and turning the palm up"),
        "Brachialis": Entry(group: "Upper arm", action: "Bending the elbow"),
        "Triceps brachii": Entry(group: "Back of upper arm", action: "Straightening the elbow, as in a push-up"),
        "Anconeus": Entry(group: "Elbow", action: "Helping straighten the elbow and steadying it"),
        "Brachioradialis": Entry(group: "Forearm", action: "Bending the elbow with the thumb pointing up"),
        "Pronator teres": Entry(group: "Forearm", action: "Turning the palm down"),
        "Flexor carpi radialis": forearmFlexor,
        "Flexor carpi ulnaris": forearmFlexor,
        "Flexor digitorum superficialis": forearmFlexor,
        "Palmaris longus": forearmFlexor,
        "Extensor carpi radialis longus": forearmExtensor,
        "Extensor carpi radialis brevis": forearmExtensor,
        "Extensor carpi ulnaris": forearmExtensor,
        "Extensor digitorum": forearmExtensor,
        "Extensor digiti minimi": forearmExtensor,
        "Abductor pollicis longus": thumbExtensor,
        "Extensor pollicis longus": thumbExtensor,
        "Extensor pollicis brevis": thumbExtensor,
        "Rectus abdominis": Entry(group: "Abdomen", action: "Curling the trunk forward and bracing the core"),
        "External abdominal oblique": Entry(group: "Side of abdomen", action: "Twisting and bending the trunk to the side, and bracing"),
        "Internal abdominal oblique": Entry(group: "Side of abdomen", action: "Twisting and bending the trunk to the side, and bracing"),
        "Inguinal ligament": Entry(group: "Groin", action: "A band of tissue along the crease between abdomen and thigh"),
        "Gluteus maximus": Entry(group: "Buttock", action: "Extending the hip when you climb, stand up or run"),
        "Gluteus medius": Entry(group: "Side of hip", action: "Keeping the pelvis level when you stand on one leg"),
        "Tensor fasciae latae": Entry(group: "Side of hip", action: "Steadying the hip and knee as you walk"),
        "Iliotibial tract": Entry(group: "Outer thigh", action: "A band of tissue that steadies the outside of the knee"),
        "Rectus femoris": Entry(group: "Front of thigh", action: "Straightening the knee and lifting the thigh"),
        "Vastus lateralis": quadriceps,
        "Vastus medialis": quadriceps,
        "Sartorius": Entry(group: "Thigh", action: "Bending the hip and knee, and turning the thigh outward"),
        "Gracilis": adductor,
        "Adductor longus": adductor,
        "Adductor magnus": adductor,
        "Pectineus": adductor,
        "Biceps femoris": hamstring,
        "Semitendinosus": hamstring,
        "Semimembranosus": hamstring,
        "Lateral patellar retinaculum": Entry(group: "Knee", action: "Holding the kneecap in its track"),
        "Medial patellar retinaculum": Entry(group: "Knee", action: "Holding the kneecap in its track"),
        "Gastrocnemius": Entry(group: "Calf", action: "Rising onto the toes and helping bend the knee"),
        "Soleus": Entry(group: "Calf", action: "Pushing off as you walk and keeping you steady when standing"),
        "Plantaris": Entry(group: "Calf", action: "Helping the calf rise onto the toes"),
        "Calcaneal tendon": Entry(group: "Back of ankle", action: "The Achilles tendon, linking the calf muscles to the heel"),
        "Tibialis anterior": Entry(group: "Shin", action: "Lifting the front of the foot as you step"),
        "Extensor digitorum longus": Entry(group: "Shin", action: "Lifting the toes and the front of the foot"),
        "Extensor digitorum longus tendon": Entry(group: "Top of foot", action: "Carrying the pull that lifts the toes"),
        "Extensor hallucis longus": Entry(group: "Shin", action: "Lifting the big toe"),
        "Fibularis longus": fibularis,
        "Fibularis brevis": fibularis,
        "Fibularis tertius": fibularis,
    ]
}
