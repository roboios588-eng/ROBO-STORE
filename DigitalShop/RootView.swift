
import SwiftUI
import PhotosUI

struct RootView: View {
    @State private var loggedIn = KeychainTokenStore.shared.read() != nil
    @State private var tab = 0
    @State private var identifier = ""
    @State private var password = ""
    @State private var username = ""
    @State private var email = ""
    @State private var isRegistering = false

    @State private var products: [APIProduct] = []
    @State private var orders: [APIOrder] = []
    @State private var selectedOrder: APIOrder?
    @State private var transactionReference = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var proofImage: UIImage?
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        Group {
            if loggedIn {
                mainTabs
            } else {
                loginScreen
            }
        }
        .tint(.blue)
        .alert("Digital Shop", isPresented: Binding(
            get: { !message.isEmpty },
            set: { if !$0 { message = "" } }
        )) {
            Button("OK") { message = "" }
        } message: {
            Text(message)
        }
    }

    private var loginScreen: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if isRegistering {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    } else {
                        TextField("Username or email", text: $identifier)
                            .textInputAutocapitalization(.never)
                    }

                    SecureField("Password", text: $password)

                    Button(busy ? "Please wait…" :
                           (isRegistering ? "Create Account" : "Sign In")) {
                        Task { await authenticate() }
                    }
                    .disabled(busy)

                    Button(isRegistering ? "Already registered? Sign In" :
                           "Create an account") {
                        isRegistering.toggle()
                    }
                }
            }
            .navigationTitle("Digital Shop")
        }
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            NavigationStack {
                productScreen
            }
            .tabItem { Label("Shop", systemImage: "bag") }
            .tag(0)

            NavigationStack {
                orderScreen
            }
            .tabItem { Label("My Orders", systemImage: "list.clipboard") }
            .tag(1)

            NavigationStack {
                accountScreen
            }
            .tabItem { Label("Account", systemImage: "person") }
            .tag(2)
        }
        .task { await refreshAll() }
    }

    private var productScreen: some View {
        List(products) { product in
            VStack(alignment: .leading, spacing: 8) {
                Text(product.name).font(.headline)
                if let description = product.description {
                    Text(description).font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(product.price, format: .currency(code: "USD"))
                    .fontWeight(.semibold)

                Button("Place Order") {
                    Task {
                        do {
                            try await APIClient.shared.createOrder(
                                productID: product.id
                            )
                            message = "Order submitted. Check My Orders for its status."
                            await loadOrders()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .navigationTitle("Products")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadProducts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private var orderScreen: some View {
        List {
            if orders.isEmpty {
                ContentUnavailableView(
                    "No Orders Yet",
                    systemImage: "shippingbox",
                    description: Text("Your orders will appear here.")
                )
            }

            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 7) {
                    Text(order.productName ?? "Order \(order.id)")
                        .font(.headline)

                    Text("Order ID: \(order.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let amount = order.amount {
                        Text(amount, format: .currency(code: "USD"))
                    }

                    Label(
                        "Order: \(order.status ?? "Pending")",
                        systemImage: "clock"
                    )

                    Label(
                        "Payment: \(order.paymentStatus ?? "Pending")",
                        systemImage: "creditcard"
                    )

                    Button("Submit Payment Proof") {
                        selectedOrder = order
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("My Orders")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadOrders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $selectedOrder) { order in
            paymentSheet(for: order)
        }
    }

    private func paymentSheet(for order: APIOrder) -> some View {
        NavigationStack {
            Form {
                Section("Order") {
                    Text(order.productName ?? order.id)
                    Text("Status: \(order.status ?? "Pending")")
                }

                Section("Payment Details") {
                    TextField(
                        "Transaction reference",
                        text: $transactionReference
                    )

                    PhotosPicker(
                        "Choose Payment Screenshot",
                        selection: $selectedPhoto,
                        matching: .images
                    )

                    if let proofImage {
                        Image(uiImage: proofImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                    }

                    Button(busy ? "Uploading…" : "Submit Proof") {
                        Task { await submitProof(order: order) }
                    }
                    .disabled(
                        busy ||
                        transactionReference.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        proofImage == nil
                    )
                }
            }
            .navigationTitle("Payment Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        selectedOrder = nil
                        selectedPhoto = nil
                        proofImage = nil
                        transactionReference = ""
                    }
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                if let data = try? await selectedPhoto.loadTransferable(
                    type: Data.self
                ), let image = UIImage(data: data) {
                    proofImage = image
                }
            }
        }
    }

    private var accountScreen: some View {
        Form {
            Section("Account") {
                Text("Signed in")
                Button("Sign Out", role: .destructive) {
                    APIClient.shared.logout()
                    loggedIn = false
                    products = []
                    orders = []
                }
            }
        }
        .navigationTitle("Account")
    }

    @MainActor
    private func authenticate() async {
        busy = true
        defer { busy = false }

        do {
            if isRegistering {
                try await APIClient.shared.register(
                    username: username,
                    email: email,
                    password: password
                )
                message = "Registration submitted. Sign in when your account is ready."
                isRegistering = false
            } else {
                try await APIClient.shared.login(
                    identifier: identifier,
                    password: password
                )
                loggedIn = true
                await refreshAll()
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func refreshAll() async {
        await loadProducts()
        await loadOrders()
    }

    @MainActor
    private func loadProducts() async {
        do {
            products = try await APIClient.shared.products()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func loadOrders() async {
        do {
            orders = try await APIClient.shared.orders()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func submitProof(order: APIOrder) async {
        guard let proofImage else { return }
        busy = true
        defer { busy = false }

        do {
            try await APIClient.shared.uploadPaymentProof(
                orderID: order.id,
                transactionReference: transactionReference,
                image: proofImage
            )
            message = "Upload completed. Refresh My Orders to check the review status."
            selectedOrder = nil
            self.proofImage = nil
            selectedPhoto = nil
            transactionReference = ""
            await loadOrders()
        } catch {
            message = error.localizedDescription
        }
    }
}
